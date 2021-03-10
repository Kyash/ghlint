#!/bin/bash -ue

declare -r LIB_DIR="$PWD/lib"
declare -r JQ_LIB_DIR="$LIB_DIR"
source "$LIB_DIR/github.sh"
source "$LIB_DIR/http.sh"
source "$LIB_DIR/json_seq.sh"
source "$LIB_DIR/logging.sh"
{
  sources="$(mktemp)"
  find "$LIB_DIR" -path "$LIB_DIR/reporter/*.sh" -o -path "$LIB_DIR/rules/*.sh" | while read -r file
  do
    echo source "$file" "$LIB_DIR"
  done > "$sources"
  source "$sources"
}

declare -r CURL_OPTS=${CURL_OPTS:--sfL}
declare -r GITHUB_API_ORIGIN=${GITHUB_API_ORIGIN:-https://api.github.com}
declare DEBUG=${DEBUG:-0}
declare XTRACE=${XTRACE:-0}
declare REPO_FILTER=${REPO_FILTER:-.}
declare REPORTER=${REPORTER:-tsv}
declare EXTENSIONS="${EXTENSIONS:-stats/commit_activity,teams,codeowners,branches}"
declare RC_FILE=${RC_FILE:-.githublintrc.json}

function usage() {
  {
    echo "Usage: $0 [-d] [-x] [-h] [-c run-control] [-f filter] [-r reporter] [-e extension[,extension]...] slug"
    echo ""
    echo "Available rules:"
    rules::list | sed -e 's/^/ - /'
    echo ""
    echo "Available reporter:"
    reporter::list | sed -e 's/^reporter::to_/ - /'
  } >&2
}

function finally () {
  logging::debug 'command exited with status %d' $?
  rm -f "$CURLRC"
}

function main() {
  while getopts "c:de:f:hr:x" opt
  do
    case "$opt" in
      c) RC_FILE="$OPTARG" ;;
      d) DEBUG=1 ;;
      e) EXTENSIONS="$OPTARG" ;;
      f) REPO_FILTER="$OPTARG" ;;
      r) REPORTER="$OPTARG" ;;
      x) XTRACE=1 ;;
      h) usage ; exit 0 ;;
      ?) usage ; exit 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  test $DEBUG -ne 0 -a -f "$RC_FILE" && {
    printf 'Run-Control file was found. '
    jq -jcM '.' "$RC_FILE"
  } | logging::debug

  if [ $XTRACE -ne 0 ]
  then
    set -x
    declare -p
    bash --version
    node --version
    curl --version
    jq --version
  fi >&2

  test $# -eq 1 || { usage ; exit 1; }

  declare -r SLUG="$1"
  local org
  org="$(echo "$SLUG" | grep '^orgs/' | sed -e 's/^orgs\///')"
  declare -r ORG="$org"

  local curlrc
  curlrc="$(mktemp)"
  declare -r CURLRC="$curlrc"
  {
    http::configure_curlrc "$CURL_OPTS" "$(test $DEBUG -ne 0 && echo '-S')"
    github::configure_curlrc
  } > "$CURLRC"

  trap finally EXIT

  cd "$(mktemp -d)"

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
    eval "$signature" describe
  done | jq -sc '{rules:.}' > "$rules_dump"

  {
    logging::info 'Fetching %s ...' "$SLUG"
    local org_dump
    org_dump="$(mktemp)"
    local resource_name
    resource_name="$(if [ -n "$ORG" ]; then echo 'organizations'; else echo 'users'; fi)"
    http::request "${GITHUB_API_ORIGIN}/$SLUG" | jq -c --arg resource_name "$resource_name" '{resources:{($resource_name):[.]}}' > "$org_dump"
    local results_dump
    results_dump="$(mktemp)"
    {
      jq -r '.rules|map(.signature)|.[]|select(test("^rules::org::"))' < "$rules_dump" | while read -r func
      do
        logging::debug 'Analysing %s about %s ...' "$ORG" "$func"
        eval "$func" analyze "$ORG" < "$org_dump" || warn '%s fail %s rule.' "$ORG" "$func"
      done | jq -sc '{results:.}' > "$results_dump"
    }
    json_seq::new "$org_dump" "$rules_dump" "$results_dump"

    local num_of_repos
    num_of_repos="$(jq -r --arg resource_name "$resource_name" '.resources[$resource_name]|first|.public_repos + .total_private_repos' "$org_dump")"
    logging::info '%s has %d repositories.' "$SLUG" "$num_of_repos"
    logging::info 'Fetching %s repositories ...' "$SLUG"
    http::list "${GITHUB_API_ORIGIN}/${SLUG}/repos" -G -d 'per_page=100' |
      jq -c "${REPO_FILTER}" |
      jq -c '.[]' | {
        local count=0
        while IFS= read -r repo
        do
          local progress_rate=$(( ++count * 100 / num_of_repos ))
          {
            local full_name
            full_name="$(echo "$repo" | jq -r '.full_name')"

            local repo_dump
            repo_dump="$(mktemp)"
            {
              logging::info '(%.0f%%) Fetching %s repository ...' "$progress_rate" "$full_name"
              github::fetch_repository "$repo" | jq -c '{resources:{repositories:[.]}}' > "$repo_dump"
            }

            local results_dump
            results_dump="$(mktemp)"
            {
              logging::info '(%.0f%%) Analysing %s repository ...' "$progress_rate" "$full_name"
              jq -r '.rules|map(.signature)|.[]|select(test("^rules::repo::"))' < "$rules_dump" | while read -r func
              do
                logging::debug 'Analysing %s repository about %s ...' "$full_name" "$func"
                eval "$func" analyze "$full_name" < "$repo_dump" || logging::warn '%s repository fail %s rule.' "$full_name" "$func"
              done | jq -sc '{results:.}' > "$results_dump"
            }

            json_seq::new "$repo_dump" "$rules_dump" "$results_dump"
          } &
        done
        wait
        logging::info 'Fitched %d repositories (Skipped %d repositories).' "$count" $((num_of_repos - count))
      }
  } | {
    eval "reporter::to_$REPORTER" "$rules_dump"
  }
}

main "$@"
