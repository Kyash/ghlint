#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/functions.sh
source "${LIB_DIR}/functions.sh"
# shellcheck source=./lib/logging.sh
source "${LIB_DIR}/logging.sh"

function http::configure_curlrc() {
  echo "$@"
}

# shellcheck disable=SC2120
function http::parse_header() {
  node "$LIB_DIR/parse_header.js" "$@"
}

function http::_request() {
  curl -q -K "$CURLRC" "$@"
}

function http::request() {
  local callback="function:passthrough"
  local argc="$#"
  local args=()
  {
    local last_arg
    last_arg="$(array::last "$@")"
    if function::exists "$last_arg"
    then
      callback="$last_arg"
      let argc-=1
    fi
  }
  args+=("${@:1:(argc)}")

  local response_dump
  response_dump="$(mktemp)"
  local header_dump
  header_dump="$(mktemp)"
  local stat_dump
  stat_dump="$(mktemp)"
  {
    set -o pipefail
    http::_request \
      -D "$header_dump" \
      -w '%{stderr}{"exitcode":%{exitcode},"errormsg":"%{errormsg}","stat":%{json}}\n' \
      "${args[@]}" 2>&1 1>&3 3>&- | {
        local pattern='/^\{"exitcode":\d+,"errormsg":"/'
        awk '! '"$pattern"' { print > "/dev/stderr" } '"$pattern"' { print }' > "$stat_dump"
      }
  } 3>&1 1>&2 | tee "$response_dump"
  local exit_status="${PIPESTATUS[0]}"

  # shellcheck disable=SC2016
  local filter='map(select((.exitcode | tostring == $exit_status) and (.stat.http_code | tostring | test("^(5\\d{2}|404)$") | not))) | length > 0'
  if [ "$exit_status" -ne 0 ] && jq -se --arg exit_status "$exit_status" "$filter" "$stat_dump" >/dev/null
  then
    local filter='
      def toi:
        "0" + . | tonumber
      ;

      map(select(type == "object"))| add |
      if (."x-ratelimit-remaining" | toi) == 0 then
        (."x-ratelimit-reset" | toi) - now | floor
      else
        -1
      end
    '
    local sleep_time
    sleep_time="$(< "$header_dump" http::parse_header | jq -r "$filter")"
    logging::trace 'sleep time %d' "$sleep_time"
    if [ "${sleep_time:-1}" -gt 0 ]
    then
      local now
      now="$(date +%s)"
      local rest_time=$((now + sleep_time))
      logging::warn \
        'Wait %d seconds because the rate limit has been exceeded. Expected to resume in %s' \
        "$sleep_time" "$(date --date "@$rest_time")"
      sleep $(("$sleep_time" + 10))
      "${FUNCNAME[0]}" "$@"
    fi
  fi

  "$callback" "$exit_status" "$response_dump" "$header_dump" "$stat_dump"
  return
}

function http::head() {
  http::request "$@" -I
}

function http::get() {
  http::request "$@" -X GET
}

function http::list() {
  local url="$1"
  shift
  local filter='
    map(select(.link?)) |
    map(.link | map(select(.rel == "last")) | map(.href.searchParams.page)) |
    flatten | first // empty
  '
  local num_of_pages
  num_of_pages=$(http::head "${url}" "$@" | http::parse_header | jq -r "$filter")
  local params
  params="$(if [ -n "${num_of_pages}" ]; then printf 'page=[1-%d]' "${num_of_pages}"; fi)"
  http::get "${url}?${params}" "$@"
}
