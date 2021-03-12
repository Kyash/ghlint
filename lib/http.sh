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

function http::request() {
  curl -K "$CURLRC" "$@"
}

function http::head() {
  http::request "$@" -I | http::parse_header
}

function http::get() {
  if http::request "$@" -X GET -Lf
  then
    return
  else
    local exit_status=$?

    local header_dump
    header_dump="$(mktemp)"
    http::request "$@" -I > "$header_dump"

    if [ ${XTRACE:-0} -ne 0 ]
    then
      < "$header_dump" http::parse_header | jq -c '.[]' |
        while read -r json
        do
          logging::trace '%s' "$json"
        done
        http::request "$@" -X GET -L | jq -c | logging::trace
    fi

    grep -q '^HTTP/[0-9.]\+ \(5\d\d\|404\)' < "$header_dump" && return $exit_status

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
      logging::warn 'Wait %d seconds because the rate limit has been exceeded.' "$sleep_time"
      sleep $(("$sleep_time" + 10))
      "${FUNCNAME[0]}" "$@"
    fi

    return $exit_status
  fi
}

function http::list() {
  local url="$1"
  shift
  local num_of_pages
  num_of_pages=$(
    http::head "${url}" "$@" |
      jq -r '
      map(select(.link?)) |
      map(.link | map(select(.rel == "last")) | map(.href.searchParams.page)) |
      flatten | first // empty
      '
  )
  params="$(if [ -n "${num_of_pages}" ]; then printf 'page=[1-%d]' "${num_of_pages}"; fi)"
  http::get "${url}?${params}" "$@"
}
