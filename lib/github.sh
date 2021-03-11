#!/bin/false

source "$LIB_DIR/http.sh"
source "$LIB_DIR/logging.sh"

function github::configure_curlrc() {
  printf -- '-H "%s"\n' "Accept: application/vnd.github.v3+json, application/vnd.github.luke-cage-preview+json"
  (
    set +x
    printf -- '-u "username:%s"\n' "$GITHUB_TOKEN"
  )
}

function github::find_blob() {
  local repo=$1
  local ref=$2
  local path=$3
  local sha
  sha=$(http::get "${GITHUB_API_ORIGIN}/repos/$repo/git/${ref}" | jq -r '.object.sha')
  test "$sha" != 'null' &&
    http::get "${GITHUB_API_ORIGIN}/repos/$repo/git/trees/${sha}?recursive=1" |
      jq -c --arg path "$path" '.tree|map(select(.path|test($path)))'
}

function github::fetch_content() {
  local url=${1:-null}
  test "${url}" != 'null' && hthttp::get "$url" | jq -r '.content | gsub("\\s"; "") | @base64d'
}

function github::parse_codeowners() {
  jq -sRc -f "$LIB_DIR/${FUNCNAME//:://}.jq"
}

function github::fetch_codeowners() {
  local repo="$1"
  local ref="$2"
  local blobs
  blobs="$(github::find_blob "$repo" "$ref" '^(|docs/|\.github/)CODEOWNERS$')"
  jq -nc --argjson blobs "${blobs:-[]}" '$blobs|.[]' |
    while IFS= read -r blob
    do
      jq -nr --argjson blob "${blob:-null}" '$blob | [.path, .url] | @tsv' | {
        IFS=$'\t' read -r path url
        github::fetch_content "$url" | github::parse_codeowners | jq -c --arg path "$path" '{$path, entries: .}'
      }
    done | jq -sc
}

function github::fetch_branches() {
  local full_name="$1"
  http::list "${GITHUB_API_ORIGIN}/repos/$full_name/branches" |
    jq -c '.[]' |
    while IFS= read -r branch
    do
      local protected
      protected="$(jq -nr --argjson branch "$branch" '$branch.protected // empty')"
      if [ "$protected" = "true" ]
      then
        local protection_url
        protection_url="$(jq -nr --argjson branch "$branch" '$branch.protection_url // empty')"
        if [ -n "$protection_url" ]
          http::get "$protection_url"
        then 
          echo 'null'
        fi | jq -c '{ protection: . }'
      else
        echo '{}'
      fi | jq -c --argjson branch "$branch" '$branch * .'
    done | jq -sc
}

function github::fetch_repository() {
  local repo="$1"
  local values=()
  while IFS='' read -r line; do values+=("$line"); done < <(echo "$repo" | jq -r '.full_name,.default_branch')
  local full_name=${values[0]}
  local default_branch=${values[1]}

  local commit_activity='{}'
  if echo "$EXTENSIONS" | grep -q '\bstats/commit_activity\b'
  then
    commit_activity=$(http::get "${GITHUB_API_ORIGIN}/repos/$full_name/stats/commit_activity" | jq -c)
    logging::debug '%s commit_activity JSON size: %d' "$full_name" ${#commit_activity}
  fi

  local teams='[]'
  if echo "$EXTENSIONS" | grep -q '\bteams\b'
  then
    teams=$(http::list "${GITHUB_API_ORIGIN}/repos/$full_name/teams" | jq -c)
    logging::debug '%s teams JSON size: %d' "$full_name" ${#teams}
  fi

  local codeowners='[]'
  if echo "$EXTENSIONS" | grep -q '\bcodeowners\b'
  then
    codeowners="$(github::fetch_codeowners "$full_name" "ref/heads/${default_branch}")"
    logging::debug '%s codeowners JSON size: %d' "$full_name" ${#codeowners}
  fi

  local branches_dump
  branches_dump="$(mktemp)"
  echo '[]' > "$branches_dump"
  if echo "$EXTENSIONS" | grep -q '\bbranches\b'
  then
    github::fetch_branches "$full_name" > "$branches_dump"
    logging::debug '%s branches JSON size: %d' "$full_name" "$(wc -c < "$branches_dump")"
  fi

  local repo_dump
  repo_dump="$(mktemp)"
  jq -cs 'add' \
    <(echo "$repo") \
    <(echo "${commit_activity:-null}" | jq -c '{stats:{commit_activity:.}}') \
    <(echo "${teams:-null}" | jq -c '{teams:.}') \
    <(echo "${codeowners:-null}" | jq -c '{codeowners:.}') \
    <(< "$branches_dump" jq -c '{branches:.}') | tee "$repo_dump"
  logging::debug '%s repository JSON size: %d' "$full_name" "$(wc -c < "$repo_dump")"
  return 0
}
