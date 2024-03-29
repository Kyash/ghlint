#!/bin/false
# shellcheck shell=bash

# shellcheck source=./src/functions.sh
source "functions.sh"
# shellcheck source=./src/http.sh
source "http.sh"
# shellcheck source=./src/jq.sh
source "jq.sh"
# shellcheck source=./src/logging.sh
source "logging.sh"
# shellcheck source=./src/url.sh
source "url.sh"

declare GITHUB_API_ORIGIN="${GITHUB_API_ORIGIN:-https://api.github.com}"

function github::configure_curl() {
  {
    printf -- '-H "%s"\n' "Accept: application/vnd.github.v3+json"
    ( set +x; printf -- '-u "username:%s"\n' "$GITHUB_TOKEN" )
  } | http::configure_curl
}

declare -p GITHUB_CURLRC_FILE &>/dev/null || {
  declare GITHUB_CURLRC_FILE="$CURLRC_FILE"
  github::configure_curl
}

function github::list() {
  local url="$1"
  shift

  # shellcheck disable=SC2016
  local filter='
    import "http" as http;

    http::parse_headers | .[1] | .link |
    if .
    then
      http::parse_link_header | map(select(.rel == "last")) | first | .href
    else
      $url
    end
  '
  github::fetch "${url}" -I "$@" | jq -Rsr --arg url "$url" "$filter" |
    url::parse | jq -r 'range(.searchParams.page // "" | if . == "" then 1 else tonumber end) | . + 1' |
    while IFS= read -r page
    do
      local opts=()
      [ "$page" -le 1 ] || opts+=(-G -d "page=$page")
      github::fetch "$url" "$@" "${opts[@]}"
    done
}

function github::fetch() {
  local url="$1"
  shift

  local cache_index_json
  cache_index_json="$(mktemp)"
  {
    ! array::includes -e '-[0-9a-zA-Z]*\(I\|G\)[0-9a-zA-z]*' -e '--get' -e '--hader' -- "$@" && http::find_cache "$url" || echo 'null'
  } >"$cache_index_json"

  local filter2='import "http" as http; . // empty | http::filter_up_to_date_cache_index(.; .)'
  if jq -e "$filter2" <"$cache_index_json" | http::respond_from_cache
  then
    logging::debug 'Respond from the cache instead of %s' "$url"
    return 0
  fi

  local filter='."last-modified" | if type == "object" then ["-H", "If-Modified-Since: \(.string)"] | @tsv else empty end'
  jq -r "$filter" <"$cache_index_json" | {
    IFS=$'\t' read -ra options || :
    http::request "$url" "$@" "${options[@]}" -g -f --fail-early github:_callback_fetch
  }
}

function github:_callback_fetch() {
  local callbacks=(
    http::callback_respond_from_cache
    github::_callback_retry_when_rate_limit_is_exceeded
    github::_callback_wait_when_accepted_response_is_sucessued
  )
  printf '%s\n' "${callbacks[@]}" | function::callback "$@"
}

function github::_callback_wait_when_accepted_response_is_sucessued() {
  local exit_status="$1"
  local stat_dump="$4"
  local args=("${@:5}")

  jq -sr 'first | .stat | [.http_code, .url_effective] | @tsv' < "$stat_dump" | {
    IFS=$'\t' read -r http_code url_effective || :
    if [ "${http_code}" = "202" ]
    then
      local sleep_time=10
      logging::debug 'The response from %s was "202 Accepted", so wait %d seconds.' "$url_effective" "$sleep_time"
      sleep "$sleep_time"
      http::request "${args[@]}"
      return
    else
      return "$exit_status"
    fi
  }
}

function github::_callback_retry_when_rate_limit_is_exceeded() {
  local args=("${@:5}")
  local exit_status=0
  http::callback_sleep_when_rate_limit_is_exceeded "$@" || exit_status="$?"
  logging::trace 'http::callback_sleep_when_rate_limit_is_exceeded returned %d' "$exit_status"
  [ "$exit_status" -eq 20 ] || return "$exit_status"
  http::request "${args[@]}"
}

function github::find_blob() {
  local repo=$1
  local ref=$2
  local path=$3
  github::fetch "${GITHUB_API_ORIGIN}/repos/$repo/git/${ref}" | jq -r '.object.sha // empty' | {
    IFS= read -r sha || :
    test -z "$sha" ||
      github::fetch "${GITHUB_API_ORIGIN}/repos/$repo/git/trees/${sha}?recursive=1" |
        jq --arg path "$path" '.tree | map(select(.path | test($path)))'
  }
}

function github::fetch_content() {
  local url="$1"
  [ "${url}" != 'null' ] || return 1
  github::fetch "$url" | jq -r '.content | gsub("\\s"; "") | @base64d'
}

function github::fetch_contents() {
  local exit_status=0
  if [ "$#" -eq 0 ]
  then
    while IFS= read -r url
    do
      github::fetch_content "$url" || exit_status="$?"
    done
  else
    for url in "$@"
    do
      github::fetch_content "$url" || exit_status="$?"
    done
  fi
  return "$exit_status"
}

function github::parse_codeowners() {
  jq -sR -f "${BASH_SOURCE[0]%.*}/${FUNCNAME[0]##*::}.jq"
}

function github::fetch_codeowners() {
  local repo="$1"
  local ref="$2"
  { github::find_blob "$repo" "$ref" '^(|docs/|\.github/)CODEOWNERS$' || { echo '[]' | http::default_response; } } | jq '.[]' | {
    local job_pids=()
    local dumps=()
    while IFS= read -r blob
    do
      local dump_file
      dump_file="$(mktemp)"
      dumps+=("$dump_file")
      jq -nr --argjson blob "${blob}" '$blob | [.path, .url] | @tsv' | {
        IFS=$'\t' read -r path url
        github::fetch_content "$url" | github::parse_codeowners | jq --arg path "$path" '{ $path, entries: . }'
      } >"$dump_file" & job_pids+=("$!")
    done
    local exit_status=0
    [ "${#job_pids[@]}" -eq 0 ] || {
      { process::wait "${job_pids[@]}" && cat "${dumps[@]}"; } || exit_status="$?"
      rm "${dumps[@]}" &
    }
    return "$exit_status"
  } | jq -s
}

function github::fetch_branches() {
  local full_name="$1"
  github::list "${GITHUB_API_ORIGIN}/repos/$full_name/branches" | jq '.[]' | {
    local job_pids=()
    local dumps=()
    while IFS= read -r branch
    do
      local dump_file
      dump_file="$(mktemp)"
      dumps+=("$dump_file")
      jq -nr --argjson branch "$branch" '$branch | [.protected, .protection_url] | map(. // "") | .[]' | {
        IFS= read -r protected
        IFS= read -r protection_url
        if [ "$protected" = "true" ]
        then
          if [ -n "$protection_url" ]
          then
            github::fetch "$protection_url" \
              -H 'Accept: application/vnd.github.luke-cage-preview+json'
          else
            echo 'null'
          fi | jq '{ protection: . }'
        else
          echo '{}'
        fi | jq --argjson branch "$branch" '$branch + .'
      } >"$dump_file" & job_pids+=("$!")
    done
    local exit_status=0
    [ "${#job_pids[@]}" -eq 0 ] || {
      { process::wait "${job_pids[@]}" && cat "${dumps[@]}"; } || exit_status="$?"
      rm "${dumps[@]}" &
    }
    return "$exit_status"
  } | jq -s
}

function github::fetch_stats.commit_activity() {
  local full_name="$1"
  github::fetch "${GITHUB_API_ORIGIN}/repos/$full_name/stats/commit_activity"
}

function github::fetch_teams() {
  local full_name="$1"
  github::list "${GITHUB_API_ORIGIN}/repos/$full_name/teams"
}

function github::fetch_repository() {
  local repo="$1"
  local extensions="$2"
  jq -nr --argjson repo "$repo" '$repo | [.full_name, .default_branch] | map(. // "") | .[]' | {
    IFS='' read -r full_name
    IFS='' read -r default_branch

    local job_pids=()
    local dumps=()
    for extension in ${extensions//,/$'\t'}
    do
      [[ "$extension" = "repository" || "$extension" = "content" ]] && continue
      local funcname="github::fetch_${extension}"
      function::exists "${funcname}" || continue
      local dump_file
      dump_file="$(mktemp)"
      echo '{}' > "$dump_file"
      dumps+=("${dump_file}")
      {
        local exit_status=0
        { "$funcname" "$full_name" "ref/heads/$default_branch" || { echo 'null' | http::default_response; } } |
          jq --arg extension "$extension" '. as $resource | null | setpath($extension | split("."); $resource)' > "$dump_file" ||
          exit_status="$?"
        logging::debug '%s %s JSON size: %d' "$full_name" "$extension" "$(wc -c < "$dump_file")"
        exit "$exit_status"
      } & job_pids+=("$!")
      LOG_ASYNC='' logging::trace '| %s() (PID: %d)' "$funcname" "$!"
    done
    LOG_ASYNC='' logging::trace '%s' "$(declare -p dumps)"

    local exit_status=0
    while IFS= read -r job_pid
    do
      wait "$job_pid" || {
        local job_status="$?"
        LOG_ASYNC='' logging::trace 'PID %d exited with status %d' "$job_pid" "$job_status"
        [ "$exit_status" -ne 22 ] || continue
        exit_status="$job_status"
      }
    done < <(printf '%s\n' "${job_pids[@]}")

    local repo_dump
    repo_dump="$(mktemp)"
    jq -s 'add' <(echo "$repo") "${dumps[@]}" | tee "$repo_dump"
    logging::debug '%s repository JSON size: %d' "$full_name" "$(wc -c < "$repo_dump")"
    rm "$repo_dump" "${dumps[@]}" &
    return "$exit_status"
  }
}

function github::fetch_organization() {
  local slug="$1"
  shift

  local resource_name="${slug%/*}"
  [ "$resource_name" = 'users' ] || resource_name='organizations'

  github::fetch "${GITHUB_API_ORIGIN}/$slug" "$@" |
    jq --arg resource_name "$resource_name" '{ resources: { ($resource_name): [.] } }'
}
