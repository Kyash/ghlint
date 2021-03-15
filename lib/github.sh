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
      logging::debug '%s' "$(declare -p num_of_pages)"
      http::request "${url}?page=[1-${num_of_pages:-1}]" "$@" -f --fail-early github::_retry_when_rate_limit_is_exceeded
    }
}

function github::fetch() {
  http::request "$@" -g -f --fail-early github::_retry_when_rate_limit_is_exceeded
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

function github::fetch_repository() {
  local repo="$1"
  jq -nr --argjson repo "$repo" '$repo | [.full_name, .default_branch] | map(. // "") | .[]' | {
    IFS='' read -r full_name
    IFS='' read -r default_branch

    local commit_activity_dump
    commit_activity_dump="$(mktemp)"
    echo '[]' > "$commit_activity_dump"
    if echo "$EXTENSIONS" | grep -q '\bstats/commit_activity\b'
    then
      {
        github::fetch "${GITHUB_API_ORIGIN}/repos/$full_name/stats/commit_activity" | jq -c > "$commit_activity_dump"
        logging::debug '%s commit_activity JSON size: %d' "$full_name" "$(wc -c < "$commit_activity_dump")"
      } &
    fi

    local teams_dump
    teams_dump="$(mktemp)"
    echo '[]' > "$teams_dump"
    if echo "$EXTENSIONS" | grep -q '\bteams\b'
    then
      {
        github::list "${GITHUB_API_ORIGIN}/repos/$full_name/teams" | jq -c > "$teams_dump"
        logging::debug '%s teams JSON size: %d' "$full_name" "$(wc -c < "$teams_dump")"
      } &
    fi

    local codeowners_dump
    codeowners_dump="$(mktemp)"
    echo '[]' > "$codeowners_dump"
    if echo "$EXTENSIONS" | grep -q '\bcodeowners\b'
    then
      {
        github::fetch_codeowners "$full_name" "ref/heads/${default_branch}" > "$codeowners_dump" 
        logging::debug '%s codeowners JSON size: %d' "$full_name" "$(wc -c < "$codeowners_dump")"
      } &
    fi

    local branches_dump
    branches_dump="$(mktemp)"
    echo '[]' > "$branches_dump"
    if echo "$EXTENSIONS" | grep -q '\bbranches\b'
    then
      {
        github::fetch_branches "$full_name" > "$branches_dump"
        logging::debug '%s branches JSON size: %d' "$full_name" "$(wc -c < "$branches_dump")"
      } &
    fi

    wait

    if [ "$XTRACE" -ne 0 ]
    then
      declare -p commit_activity_dump teams_dump codeowners_dump branches_dump | while IFS= read -r line
      do
        logging::trace '%s' "$line"
      done
    fi

    local repo_dump
    repo_dump="$(mktemp)"
    jq -cs 'add' \
      <(echo "$repo") \
      <(< "${commit_activity_dump}" jq -c '{ stats: { commit_activity: . } }') \
      <(< "${teams_dump}" jq -c '{ teams: . }') \
      <(< "${codeowners_dump}" jq -c '{ codeowners: . }') \
      <(< "$branches_dump" jq -c '{ branches: . }') | tee "$repo_dump"
    logging::debug '%s repository JSON size: %d' "$full_name" "$(wc -c < "$repo_dump")"
  }
}
