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
    printf -- '-H "%s"\n' "Accept: application/vnd.github.v3+json, application/vnd.github.luke-cage-preview+json"
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
  # shellcheck disable=SC2016
  local filter2='
    import "url" as url;

    . as $url |
    (.searchParams.page // "" | if . == "" then 1 else tonumber end) as $num_of_pages | range($num_of_pages) | . + 1
  '
  github::fetch "${url}" -I "$@" | jq -Rsr --arg url "$url" "$filter" | url::parse | jq -r "$filter2" | while IFS= read -r page
  do
    github::fetch "$url" "$@" -G -d "page=$page"
  done
}

function github::fetch() {
  local url="$1"
  shift

  local cache_index_json
  cache_index_json="$(mktemp)"
  {
    flock -s 6
    http::find_cache "$url" || echo 'null'
  } 6>>"$HTTP_CACHE_INDEX_FILE" >"$cache_index_json" <"$HTTP_CACHE_INDEX_FILE"

  local filter2='import "http" as http; . // empty | http::filter_up_to_date_cache_index(.; .) | .file'
  IFS='' read -r cache_file < <(jq -r "$filter2" "$cache_index_json") || :
  if [ -f "$cache_file" ]
  then
    cat "$cache_file"
    logging::debug 'Respond from the cache instead of %s' "$url"
    return 0
  fi || :

  local filter='."last-modified" | if type == "object" then ["-H", "If-Modified-Since: \(.string)"] | @tsv else empty end'
  IFS=$'\t' read -ra options < <(jq -r "$filter" "$cache_index_json") || :
  http::request "$url" "$@" "${options[@]}" -g -f --fail-early github:_callback_fetch
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
  local filter='.content | gsub("\\s"; "") | @base64d'
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
  {
    { github::find_blob "$repo" "$ref" '^(|docs/|\.github/)CODEOWNERS$' || { echo '[]' | http::default_response; } } | jq '.[]' |
    while IFS= read -r blob
    do
      {
        IFS=$'\t' read -r path url
        github::fetch_content "$url" | github::parse_codeowners | jq --arg path "$path" '{ $path, entries: . }'
      } < <(jq -nr --argjson blob "${blob}" '$blob | [.path, .url] | @tsv')
    done
  } | jq -s
}

function github::fetch_branches() {
  local full_name="$1"
  github::list "${GITHUB_API_ORIGIN}/repos/$full_name/branches" | jq '.[]' | {
    while IFS= read -r branch
    do
      {
        IFS= read -r protected
        IFS= read -r protection_url
        if [ "$protected" = "true" ]
        then
          if [ -n "$protection_url" ]
          then
            github::fetch "$protection_url"
          else
            echo 'null'
          fi | jq -c '{ protection: . }'
        else
          echo '{}'
        fi | jq -c --argjson branch "$branch" '$branch + .'
      } < <(jq -nr --argjson branch "$branch" '$branch | [.protected, .protection_url] | map(. // "") | .[]')
    done
  } | jq -sc
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
      } &
      job_pids+=("$!")
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

    return "$exit_status"
  }
}

function github::fetch_organization() {
  local slug="$1"
  shift
  github::fetch "${GITHUB_API_ORIGIN}/$slug" "$@" |
    jq -c --arg resource_name "${slug%/*}" '{ resources: { ($resource_name): [.] } }'
}
