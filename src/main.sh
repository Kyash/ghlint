#!/bin/bash

set -ueo pipefail

LOG_LEVEL="${GITHUBLINT_LOG_LEVEL:-6}"
# shellcheck disable=SC2034
LOG_ASYNC="${GITHUBLINT_LOG_ASYNC:-true}"

function path::isabsolute() {
  test "${1:0:1}" = "/"
}

function path::absolutisation() {
  (
    set -ue
    local value="${1}"
    [ -n "$value" ] || exit 1
    cd "$(dirname "$value")" && echo -n "${PWD%/}/"
  ) && basename "${1#/}"
}

function path::realize() {
  local file="$1"
  [ -L "$file" ] || { echo "$file" && return 0; }
  real_file="$(readlink -f "$file")"
  if path::isabsolute "$real_file"
  then
    echo "$real_file"
  else
    echo "$(dirname "$file")/$real_file"
  fi
}

SHELL_SOURCE="$(path::absolutisation "$(path::realize "${BASH_SOURCE[0]}")")"
declare -r SHELL_SOURCE
PATH="$(dirname "$SHELL_SOURCE"):$PATH"
# shellcheck source=./src/github.sh
source "github.sh"
# shellcheck source=./src/http.sh
source "http.sh"
# shellcheck source=./src/json_seq.sh
source "json_seq.sh"
# shellcheck source=./src/jq.sh
source "jq.sh"
# shellcheck source=./src/logging.sh
source "logging.sh"
# shellcheck source=./src/rules.sh
source "reporter.sh"
# shellcheck source=./src/reporter.sh
source "rules.sh"

{
  sources_file="$(mktemp)"
  {
    reporter::sources
    rules::sources
  } | while read -r file
  do
    echo source "$file"
  done > "$sources_file"
  # shellcheck source=/dev/null
  source "$sources_file"
}

function usage() {
  {
    echo "Usage: $(basename "$0") [-d] [-x] [-h] [-p parallelism] [-c run-control] [-f filter] [-r reporter] [-e extension[,extension]...] slug"
    echo ""
    echo "Available rules:"
    rules::list | sed -e 's/^/ - /'
    echo ""
    echo "Available reporter:"
    reporter::list | sed -e 's/^reporter::to_/ - /'
  } >&2
}

function main() {
  local debug="${GITHUBLINT_DEBUG:-0}"
  local xtrace="${GITHUBLINT_XTRACE:-0}"
  local repo_filter="${GITHUBLINT_REPO_FILTER:-.}"
  local reporter="${GITHUBLINT_REPORTER:-tsv}"
  local extensions="${GITHUBLINT_EXTENSIONS:-stats.commit_activity,teams,codeowners,branches}"
  local rc_file="${GITHUBLINT_RC_FILE:-.githublintrc.json}"
  local parallelism="${GITHUBLINT_PARALLELISM:-100}"

  trap finally EXIT

  while getopts "c:de:f:hp:r:x" opt
  do
    case "$opt" in
      c) rc_file="$OPTARG" ;;
      d) debug=1 ;;
      e) extensions="$OPTARG" ;;
      f) repo_filter="$OPTARG" ;;
      p) parallelism="$OPTARG" ;;
      r) reporter="$OPTARG" ;;
      x) xtrace=1 ;;
      h) usage ; exit 0 ;;
      ?) usage ; exit 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  [ "${debug:-0}" -eq 0 ] || {
    [ "${LOG_LEVEL:-0}" -ge 7 ] || LOG_LEVEL=7
    set -E
    trap inspect ERR
  }

  [ "${xtrace:-0}" -eq 0 ] || {
    [ "${LOG_LEVEL:-0}" -ge 9 ] || LOG_LEVEL=9
    BASH_XTRACEFD=4
    PS4='+ ${BASH_SOURCE}:${LINENO}${FUNCNAME:+ - ${FUNCNAME}()} | '
    set -x
  }

  local profile_dir
  profile_dir="$HOME/.githublint/$(echo "$GITHUB_TOKEN" | md5sum | cut -d' ' -f1)"
  declare -r PROFILE_DIR="$profile_dir"
  http::mkcache "$PROFILE_DIR" >/dev/null

  [ "${LOG_LEVEL:-0}" -lt 8 ] || {
    {
      declare -p
      bash --version
      node --version
      curl --version
      jq --version
    } | (
      set +x
      while IFS= read -r line
      do
        LOG_ASYNC='' logging::trace '%s' "$line"
      done
    )
  }

  test $# -eq 1 || { usage ; exit 1; }

  local rc_file
  rc_file="$(path::absolutisation "$rc_file")"

  cd "$(mktemp -d)"

  if [ -f "$rc_file" ]
  then
    cat < "$rc_file"
  else
    echo '{}'
  fi > ".githublintrc.json"

  [ "${debug:-0}" -eq 0 ] || {
    printf 'Run-Control file was found. '
    jq -njM 'import ".githublintrc" as $rc; $rc'
  } | logging::debug

  http::clean_cache &
  local cleaning_job_pid="$!"

  local rules_dump
  rules_dump="$(mktemp)"
  rules::list | while read -r signature
  do
    "$signature" describe
  done | jq -s '{ rules: . }' > "$rules_dump"

  local results_fifo="results"
  mkfifo "$results_fifo"
  {
    jq --seq '.results | length' | jq -esr 'add | . == 0' >/dev/null
  } <"$results_fifo" &
  local statistics_job_pid="$!"

  {
    local slug="$1"
    local org="${slug#*/}"

    local lock_file
    lock_file="$(mktemp)"

    logging::info 'Fetching %s ...' "$slug"
    local org_dump
    org_dump="$(mktemp)"
    github::fetch_organization "$slug" > "$org_dump"
    local results_dump
    results_dump="$(mktemp)"
    jq -r '.rules | map(.signature) | .[] | select(test("^rules::org::"))' < "$rules_dump" |
      while read -r func
      do
        logging::debug 'Analysing %s about %s ...' "$org" "$func"
        "$func" analyze < "$org_dump" || warn '%s fail %s rule.' "$org" "$func"
      done | jq -s '{ results: . }' > "$results_dump"
    {
      flock 6
      json_seq::new "$org_dump" "$rules_dump" "$results_dump"
    } 6>> "$lock_file"

    jq -r \
      '.resources | .organizations + .users | (. // [])[] | [.repos_url, .public_repos + .total_private_repos] | @tsv' \
      <"$org_dump" | {
        while IFS=$'\t' read -r repos_url num_of_repos
        do
          logging::info '%s has %d repositories.' "$slug" "$num_of_repos"
          logging::info 'Fetching %s repositories ...' "$slug"
          github::list "$repos_url" -G -d 'per_page=100' | jq "${repo_filter}" | jq '(. // [])[]' | {
            local count=0
            local job_pids=()
            while IFS= read -r repo
            do
              local progress_rate=$(( ++count * 100 / num_of_repos ))
              logging::debug 'Running %d jobs ...' "$(process::count_running_jobs)"
              while [ "$parallelism" -gt 0 ] && [ "$(process::count_running_jobs)" -gt "$parallelism" ]
              do
                logging::debug 'Wait (running %d jobs).' "$(process::count_running_jobs)"
                sleep .5
                logging::debug 'Resume (running %d jobs).' "$(process::count_running_jobs)"
              done
              {
                local full_name
                full_name="$(echo "$repo" | jq -r '.full_name')"

                local repo_dump
                repo_dump="$(mktemp)"
                logging::info '(%.0f%%) Fetching %s repository ...' "$progress_rate" "$full_name"
                github::fetch_repository "$repo" "$extensions" |
                  jq '{ resources: { repositories: [.] } }' > "$repo_dump"

                local results_dump
                results_dump="$(mktemp)"
                logging::info '(%.0f%%) Analysing %s repository ...' "$progress_rate" "$full_name"
                jq -r '.rules | map(.signature) | .[] | select(test("^rules::repo::"))' < "$rules_dump" | while read -r func
                do
                  logging::debug 'Analysing %s repository about %s ...' "$full_name" "$func"
                  "$func" analyze < "$repo_dump" || logging::warn '%s repository fail %s rule.' "$full_name" "$func"
                done | jq -s '{results:.}' > "$results_dump"

                {
                  flock 6
                  json_seq::new "$repo_dump" "$rules_dump" "$results_dump"
                } 6>> "$lock_file"
              } &
              if [ "$parallelism" -lt 1 ]
              then
                wait "$!"
              else
                job_pids+=("$!")
              fi
            done
            local exit_status=0
            wait "${job_pids[@]}" || exit_status="$?"
            LOG_ASYNC='' logging::info 'Fitched %d repositories (Skipped %d repositories).' "$count" $((num_of_repos - count))
            [ "$exit_status" -eq 0 ] || exit "$exit_status"
          }
        done
      }
  } | tee "$results_fifo" | "reporter::to_$reporter" "$rules_dump" &
  local analysing_job_pid="$!"

  wait "$cleaning_job_pid" || :
  wait "$analysing_job_pid" || {
    local exit_status="$?"
    [ "$exit_status" -ne 1 ] || exit_status=111
    exit "$exit_status"
  }
  wait "$statistics_job_pid"
}

function inspect() {
  LOG_ASYNC='' logging::debug \
    '%s function caught an error on line %d (status: %d).' "${FUNCNAME[1]}" "${BASH_LINENO[0]}" "$?"
  LOG_ASYNC='' logging::debug '%s' "$(declare -p FUNCNAME)"
}

function finally () {
  local exit_status="$?"
  LOG_ASYNC='' logging::debug 'command exited with status %d' "$exit_status"
  rm -f "$CURLRC_FILE"
}

main "$@"
