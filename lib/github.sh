#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/http.sh
source "$LIB_DIR/http.sh"
# shellcheck source=./lib/logging.sh
source "$LIB_DIR/logging.sh"

function github::configure_curlrc() {
  printf -- '-H "%s"\n' "Accept: application/vnd.github.v3+json, application/vnd.github.luke-cage-preview+json"
  (
    set +x
    printf -- '-u "username:%s"\n' "$GITHUB_TOKEN"
  )
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
  http::request -I "${url}" "$@" | 
    jq -L"$JQ_LIB_DIR" -Rscr --arg url "$url" "$filter" |
    http::parse_url | jq -r '.searchParams.page // ""' | {
      IFS= read -r num_of_pages
      logging::trace '%s' "$(declare -p num_of_pages)"
      http::request "${url}?page=[1-${num_of_pages:-1}]" "$@" -f --fail-early github::_retry_when_rate_limit_is_exceeded
    }
}

function github::fetch() {
  local url="$1"
  shift
  local filter='."last-modified" | if type == "object" then ["-H", "If-Modified-Since: \(.string)"] | @tsv else empty end'
  { http::find_cache "$url" < "$CACHE_INDEX_FILE" || echo 'null'; } | jq -r "$filter" | {
    IFS=$'\t' read -ra options || :
    http::request "$url" "$@" "${options[@]}" -g -f --fail-early github:_callback_fetch
  }
}

function github:_callback_fetch() {
  http::respond_from_cache "$@"
  github::_retry_when_rate_limit_is_exceeded "$@"
}

function github::_retry_when_rate_limit_is_exceeded() {
  http::sleep_when_rate_limit_is_exceeded "$@"
  if [ "$?" -eq 20 ]
  then
    local args=("${@:5}")
    "${FUNCNAME[1]}" "${args[@]}"
  fi
}

function github::find_blob() {
  local repo=$1
  local ref=$2
  local path=$3
  github::fetch "${GITHUB_API_ORIGIN}/repos/$repo/git/${ref}" | jq -r '.object.sha // empty' | {
    IFS= read -r sha
    test -n "$sha" &&
      github::fetch "${GITHUB_API_ORIGIN}/repos/$repo/git/trees/${sha}?recursive=1" |
        jq -c --arg path "$path" '.tree|map(select(.path|test($path)))'
  }
}

function github::fetch_content() {
  local url=${1:-null}
  test "${url}" != 'null' && github::fetch "$url" | jq -r '.content | gsub("\\s"; "") | @base64d'
}

function github::parse_codeowners() {
  jq -sRc -f "$LIB_DIR/${FUNCNAME//:://}.jq"
}

function github::fetch_codeowners() {
  local repo="$1"
  local ref="$2"
  github::find_blob "$repo" "$ref" '^(|docs/|\.github/)CODEOWNERS$' | jq -c '.[]' |
    while IFS= read -r blob
    do
      jq -nr --argjson blob "${blob:-null}" '$blob | [.path, .url] | @tsv' | {
        IFS=$'\t' read -r path url
        github::fetch_content "$url" | github::parse_codeowners | jq -c --arg path "$path" '{ $path, entries: . }'
      }
    done | jq -sc
}

function github::fetch_branches() {
  local full_name="$1"
  github::list "${GITHUB_API_ORIGIN}/repos/$full_name/branches" | jq -c '.[]' | while IFS= read -r branch
  do
    jq -nr --argjson branch "$branch" '$branch | [.protected, .protection_url] | map(. // "") | .[]' | {
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
    }
  done | jq -sc
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
  jq -nr --argjson repo "$repo" '$repo | [.full_name, .default_branch] | map(. // "") | .[]' | {
    IFS='' read -r full_name
    IFS='' read -r default_branch

    local dumps=()
    for extension in ${EXTENSIONS//,/$'\t'}
    do
      [[ "$extension" = "repository" || "$extension" = "content" ]] && continue
      local funcname="github::fetch_${extension}"
      function::exists "${funcname}" || continue
      local dump_file
      dump_file="$(mktemp)"
      echo '{}' > "$dump_file"
      dumps+=("${dump_file}")
      {
        "$funcname" "$full_name" "ref/heads/$default_branch" |
          jq -c --arg extension "$extension" '. as $resource | null | setpath($extension | split("."); $resource)' > "$dump_file"
        logging::debug '%s %s JSON size: %d' "$full_name" "$extension" "$(wc -c < "$dump_file")"
      } &
    done

    logging::trace '%s' "$(declare -p dumps)"

    wait

    local repo_dump
    repo_dump="$(mktemp)"
    jq -cs 'add' <(echo "$repo") "${dumps[@]}" | tee "$repo_dump"
    logging::debug '%s repository JSON size: %d' "$full_name" "$(wc -c < "$repo_dump")"
  }
}
