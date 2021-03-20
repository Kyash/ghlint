#!/bin/bash

set -ueo pipefail

declare LOG_LEVEL=${LOG_LEVEL:-6}
declare LOG_ASYNC=${LOG_ASYNC:-true}

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
  real_file="$(readlink "$file")"
  if path::isabsolute "$real_file"
  then
    echo "$real_file"
  else
    echo "$(dirname "$file")/$real_file"
  fi
}

SCRIPT_FULL_PATH="$(path::absolutisation "$(path::realize "${BASH_SOURCE[0]}")")"
LIB_DIR="$(dirname "$SCRIPT_FULL_PATH")"
PATH="$LIB_DIR:$PATH"
declare -r LIB_DIR
# shellcheck disable=SC2034
declare -r JQ_LIB_DIR="$LIB_DIR"
# shellcheck source=./lib/github.sh
source "github.sh"
# shellcheck source=./lib/http.sh
source "http.sh"
# shellcheck source=./lib/json_seq.sh
source "json_seq.sh"
# shellcheck source=./lib/logging.sh
source "logging.sh"
{
  sources="$(mktemp)"
  find "$LIB_DIR" -path "$LIB_DIR/reporter/*.sh" -o -path "$LIB_DIR/rules/*.sh" | while read -r file
  do
    echo source "$file"
  done > "$sources"
  # shellcheck source=/dev/null
  source "$sources"
}

declare -r CURL_OPTS=${CURL_OPTS:--s}
declare -r GITHUB_API_ORIGIN=${GITHUB_API_ORIGIN:-https://api.github.com}
declare DEBUG=${DEBUG:-0}
declare XTRACE=${XTRACE:-0}
declare REPO_FILTER=${REPO_FILTER:-.}
declare REPORTER=${REPORTER:-tsv}
declare EXTENSIONS="${EXTENSIONS:-stats.commit_activity,teams,codeowners,branches}"
declare RC_FILE=${RC_FILE:-.githublintrc.json}
declare CURLRC=
declare PARALLELISM=${PARALLELISM:-100}
declare PROFILE_DIR=
declare CACHE_DIR=
declare CACHE_INDEX_FILE=

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
  trap finally EXIT

  local profile_dir
  profile_dir="$HOME/.githublint/$(echo "$GITHUB_TOKEN" | md5sum | cut -d' ' -f1)"
  readonly PROFILE_DIR="$profile_dir"
  readonly CACHE_DIR="$PROFILE_DIR/cache"
  readonly CACHE_INDEX_FILE="$CACHE_DIR/index.txt"
  mkdir -p "$CACHE_DIR"
  touch "$CACHE_INDEX_FILE"

  while getopts "c:de:f:hp:r:x" opt
  do
    case "$opt" in
      c) RC_FILE="$OPTARG" ;;
      d) DEBUG=1 ;;
      e) EXTENSIONS="$OPTARG" ;;
      f) REPO_FILTER="$OPTARG" ;;
      p) PARALLELISM="$OPTARG" ;;
      r) REPORTER="$OPTARG" ;;
      x) XTRACE=1 ;;
      h) usage ; exit 0 ;;
      ?) usage ; exit 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  [ $DEBUG -eq 0 ] || {
    LOG_LEVEL=7
    set -E
    trap inspect ERR
    ! [ -f "$RC_FILE" ] || {
      printf 'Run-Control file was found. '
      jq -jcM '.' "$RC_FILE"
    } | logging::debug
  }

  [ "${XTRACE:-0}" -eq 0 ] || {
    LOG_LEVEL=9
    BASH_XTRACEFD=4
    PS4='+ ${BASH_SOURCE}:${LINENO}${FUNCNAME:+ - ${FUNCNAME}()} | '
    set -x
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

  declare -r SLUG="$1"
  local org
  org="$(echo "$SLUG" | grep '^orgs/' || : | sed -e 's/^orgs\///')"
  declare -r ORG="$org"

  CURLRC="$(mktemp)"
  {
    http::configure_curlrc "$CURL_OPTS" "$(test $DEBUG -ne 0 && echo '-S')"
    github::configure_curlrc
  } > "$CURLRC"

  cd "$(mktemp -d)"

  http::clean_cache &

  if [ -f "$RC_FILE" ]
  then
    cat < "$RC_FILE"
  else
    echo '{}'
  fi > ".githublintrc.json"

  local rules_dump
  rules_dump="$(mktemp)"
  rules::list | while read -r signature
  do
    "$signature" describe
  done | jq -sc '{rules:.}' > "$rules_dump"

  {
    local lock_file
    lock_file="$(mktemp)"
    logging::info 'Fetching %s ...' "$SLUG"
    local org_dump
    org_dump="$(mktemp)"
    local resource_name
    if [ -n "$ORG" ]
    then
      resource_name='organizations'
    else
      resource_name='users'
    fi
    github::fetch "${GITHUB_API_ORIGIN}/$SLUG" |
      jq -c --arg resource_name "$resource_name" '{ resources: { ($resource_name): [.] } }' > "$org_dump"
    local results_dump
    results_dump="$(mktemp)"
    {
      jq -r '.rules | map(.signature) | .[] | select(test("^rules::org::"))' < "$rules_dump" | while read -r func
      do
        logging::debug 'Analysing %s about %s ...' "$ORG" "$func"
        "$func" analyze "$ORG" < "$org_dump" || warn '%s fail %s rule.' "$ORG" "$func"
      done | jq -sc '{ results: . }' > "$results_dump"
    }
    {
      flock 6
      json_seq::new "$org_dump" "$rules_dump" "$results_dump"
    } 6>> "$lock_file"

    function process::count_running_jobs() {
      jobs -pr | wc -l
    }

    local num_of_repos
    num_of_repos="$(jq -r --arg resource_name "$resource_name" '.resources[$resource_name] | first | .public_repos + .total_private_repos' "$org_dump")"
    logging::info '%s has %d repositories.' "$SLUG" "$num_of_repos"
    logging::info 'Fetching %s repositories ...' "$SLUG"
    github::list "${GITHUB_API_ORIGIN}/${SLUG}/repos" -G -d 'per_page=100' | jq -c "${REPO_FILTER}" | jq -c '(. // [])[]' | {
      local count=0
      while IFS= read -r repo
      do
        local progress_rate=$(( ++count * 100 / num_of_repos ))
        logging::debug 'Running %d jobs ...' "$(process::count_running_jobs)"
        while [ "$PARALLELISM" -gt 0 ] && [ "$(process::count_running_jobs)" -gt "$PARALLELISM" ]
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
          {
            logging::info '(%.0f%%) Fetching %s repository ...' "$progress_rate" "$full_name"
            github::fetch_repository "$repo" | jq -c '{ resources: { repositories: [.] } }' > "$repo_dump"
          }

          local results_dump
          results_dump="$(mktemp)"
          {
            logging::info '(%.0f%%) Analysing %s repository ...' "$progress_rate" "$full_name"
            jq -r '.rules | map(.signature) | .[] | select(test("^rules::repo::"))' < "$rules_dump" | while read -r func
            do
              logging::debug 'Analysing %s repository about %s ...' "$full_name" "$func"
              "$func" analyze "$full_name" < "$repo_dump" || logging::warn '%s repository fail %s rule.' "$full_name" "$func"
            done | jq -sc '{results:.}' > "$results_dump"
          }

          {
            flock 6
            json_seq::new "$repo_dump" "$rules_dump" "$results_dump"
          } 6>> "$lock_file"
        } &
        if [ "$PARALLELISM" -lt 1 ]
        then
          wait "$!"
        fi
      done
      wait
      LOG_ASYNC='' logging::info 'Fitched %d repositories (Skipped %d repositories).' "$count" $((num_of_repos - count))
    }
  } | "reporter::to_$REPORTER" "$rules_dump"
}

function inspect() {
  LOG_ASYNC='' logging::debug \
    '%s function caught an error on line %d (status: %d).' "${FUNCNAME[1]}" "${BASH_LINENO[0]}" "$?"
  LOG_ASYNC='' logging::debug '%s' "$(declare -p FUNCNAME)"
}

function finally () {
  LOG_ASYNC='' logging::debug 'command exited with status %d' $?
  rm -f "$CURLRC"
}

main "$@"
