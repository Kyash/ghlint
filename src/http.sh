#!/bin/false
# shellcheck shell=bash

# shellcheck source=./src/functions.sh
source "functions.sh"
# shellcheck source=./src/jq.sh
source "jq.sh"
# shellcheck source=./src/logging.sh
source "logging.sh"

declare CURL_OPTS=${CURL_OPTS:--s}

function http::chcache() {
  local cache_dir
  cache_dir="${1}/cache"
  mkdir -p "$cache_dir"
  HTTP_CACHE_DIR="$cache_dir"
  HTTP_CACHE_INDEX_FILE="$HTTP_CACHE_DIR/index.txt"
  touch "$HTTP_CACHE_INDEX_FILE"
}

declare -p HTTP_CACHE_DIR &>/dev/null || {
  declare HTTP_CACHE_DIR=''
  declare HTTP_CACHE_INDEX_FILE=''
  http::chcache "$(mktemp -d)"
}

function http::configure_curl() {
  {
    [ "${LOG_LEVEL:-0}" -lt 7 ] || echo '-S'
    cat
  } | tee "$CURLRC_FILE" |
  if [ "${LOG_LEVEL:-0}" -gt 7 ]
  then
    (
      set +x
      while IFS= read -r line
      do
        LOG_ASYNC='' logging::trace '%s' "$line"
      done
    )
  fi
}

declare -p CURLRC_FILE &>/dev/null || {
  declare CURLRC_FILE=''
  CURLRC_FILE="$(mktemp)"
  http::configure_curl </dev/null
}

function http::_request() {
  curl -q -K "$CURLRC_FILE" "${CURL_OPTS[@]}" "$@"
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
  local exit_status=0
  (
    set -o pipefail
    {
      http::_request \
        -D "$header_dump" \
        -w '%{stderr}{"exitcode":%{exitcode},"errormsg":"%{errormsg}","stat":%{json}}\n' \
        "${args[@]}" 2>&1 1>&3 3>&- | {
          local pattern='/^\{"exitcode":\d+,"errormsg":"/'
          awk '! '"$pattern"' { print > "/dev/stderr" } '"$pattern"' { print }' > "$stat_dump"
        }
    } 3>&1 1>&2 | tee "$response_dump"
  ) || exit_status="$?"

  [ "${LOG_LEVEL:-0}" -lt 8 ] || {
    declare -p exit_status response_dump header_dump stat_dump args callback | while IFS= read -r line
    do
      LOG_ASYNC='' logging::trace '%s' "$line"
    done
  }

  local functions=(
    http::callback_store_cache
    "$callback"
  )
  printf '%s\n' "${functions[@]}" |
    function::callback "$exit_status" "$response_dump" "$header_dump" "$stat_dump" "$@"
  return
}

function http::clean_cache() {
  local dumps=()
  dumps+=("$(mktemp)" "$(mktemp)")
  local new_cache_index_file="${dumps[0]}"
  local outdated_files="${dumps[1]}"
  {
    flock -s 6
    jq -Rr 'import "http" as http; http::filter_up_to_date_cache_index(http::parse_cache_index; ."last-modified")' \
      >"$new_cache_index_file" 2>"$outdated_files"
    flock -x 6
    cat <"$new_cache_index_file" >"$HTTP_CACHE_INDEX_FILE"
    logging::debug '%s' "Updated cache index file."
  } 6>>"$HTTP_CACHE_INDEX_FILE" <"$HTTP_CACHE_INDEX_FILE"

  jq -r < "$outdated_files" | {
    local count=0
    while IFS= read -r file
    do
      ! [ -f "$file" ] || rm "$file"
      count=$(( count + 1 ))
    done
    logging::debug 'Deleted %d expired cache files.' "$count"
  }
}

function http::find_cache() {
  local url_effective="$1"
  local index
  index="$(echo "$url_effective" | crypto::hash)"
  grep "^${index}\t" |
    jq -R 'import "http" as http; http::parse_cache_index' |
    jq -esr --arg url "$url_effective" \
      '.[] | select(.url_effective == $url) | reduce . as $e (null; if ($e.date.unixtime > .date.unixtime) then $e else . end)'
}

function http::respond_from_cache() {
  jq -r '.file' | {
    IFS='' read -r file
    [ -f "$file" ] || return 1
    cat "$file"
  }
  return 0
}

function http::callback_respond_from_cache() {
  local exit_status="$1"
  local stat_dump="$4"
  jq -sr 'map([.stat.http_code, .stat.url_effective] | @tsv) | .[]' < "$stat_dump" | {
    while IFS=$'\t' read -r http_code url_effective
    do
      if [ "$http_code" = "304" ]
      then
        {
          flock -s 6
          http::find_cache "$url_effective" | http::respond_from_cache &&
            logging::debug 'Respond from the cache instead of %s' "$url_effective"
        } 6>>"$HTTP_CACHE_INDEX_FILE" <"$HTTP_CACHE_INDEX_FILE" || return 24
      fi
    done
  }
  return "$exit_status"
}

function http::callback_sleep_when_rate_limit_is_exceeded() {
  local header_dump="$3"
  local stat_dump="$4"

  (
    set -eo pipefail
    local filter='map([.stat.http_code, .stat.size_download, .stat.size_header, .stat.url_effective] | @tsv) | .[]'
    jq -sr "$filter" < "$stat_dump" | {
      local total_size_header=0
      local total_size_body=0
      while IFS=$'\t' read -r http_code size_body size_header url_effective
      do
        if [ "${http_code:0:1}" = "4" ]
        then
          stream::slice "$total_size_header" "$size_header" < "$header_dump" | {
            jq -Rsr \
              '
                import "http" as http;

                http::parse_headers | .[1] |
                select(."x-ratelimit-remaining" and ."x-ratelimit-reset") |
                if (."x-ratelimit-remaining" | tonumber) == 0 then
                  (."x-ratelimit-reset" | tonumber) - now | floor
                else
                  empty
                end
              '
          }
        fi
        total_size_header=$(( total_size_header + size_header ))
        total_size_body=$(( total_size_body + size_body ))
      done
    } | jq -sr 'max // empty' | {
      IFS= read -r sleep_time || :
      LOG_ASYNC='' logging::trace 'sleep time %d' "${sleep_time:-0}"
      if [ "${sleep_time:-0}" -gt 0 ]
      then
        local now
        now="$(date +%s)"
        local rest_time=$((now + sleep_time))
        logging::warn \
          'Wait %d seconds because the rate limit has been exceeded. Expected to resume in %s' \
          "$sleep_time" "$(date --date "@$rest_time")"
        sleep $(("$sleep_time" + 5))
        logging::debug 'Resume'
        return 20
      fi
    }
  ) || {
    local exit_status="$?"
    [ "$exit_status" = "$1" ] || return "$exit_status" 
  }
  return "$1"
}

function http::callback_store_cache() {
  local exit_status="$1"
  local response_dump="$2"
  local header_dump="$3"
  local stat_dump="$4"
  local args=("${@:5}")
  test "$exit_status" -eq 0 || return "$exit_status"
  jq -esr 'map([.exitcode, .stat.http_code, .stat.method, .stat.size_download, .stat.size_header, .stat.url_effective] | @tsv) | .[]' "$stat_dump" | {
    local total_size_header=0
    local total_size_body=0
    while IFS=$'\t' read -r exitcode http_code method size_body size_header url_effective
    do
      LOG_ASYNC='' logging::trace '%d,%d,%s,%d,%d,%s' "$exitcode" "$http_code" "$method" "$size_body" "$size_header" "$url_effective"
      if [ "$exitcode" -eq 0 ] && [ "${method}" != "HEAD" ] && [ "${http_code:0:1}" = '2' ] && [ "${http_code}" != '204' ]
      then
        stream::slice "$total_size_header" "$size_header" < "$header_dump" | {
          jq -Rsr --arg url_effective "$url_effective" \
            '
              import "http" as http;

              http::parse_headers | .[1] |
              select(."cache-control" // "" | test("\\bno-store\\b") | not) |
              ([
                $url_effective,
                ."last-modified",
                .etag,
                ."cache-control",
                .pragma,
                .vary
              ] | @tsv),
              $url_effective,
              .date // "",
              .expires // ""
            '
        } | {
          IFS= read -r entry && {
            IFS= read -r url_effective
            IFS= read -r date || :
            IFS= read -r expires || :
            local cache_filename
            cache_filename="$(echo "$entry" | crypto::hash)"
            local index
            index="$(echo "$url_effective" | crypto::hash)"
            local cache_file="$HTTP_CACHE_DIR/$cache_filename"
            {
              flock 6
              if [ ! -e "$cache_file" ]
              then
                touch "$cache_file"
                stream::slice "$total_size_body" "$size_body" < "$response_dump" > "$cache_file"
                printf '%s\t%s\t%s\t%s\t%s\n' "$index" "$entry" "$expires" "$date" "$cache_file" \
                  >>"$HTTP_CACHE_INDEX_FILE"
              fi
            } 6>>"$HTTP_CACHE_INDEX_FILE"
          }
        }
      fi
      total_size_header=$(( total_size_header + size_header ))
      if [ "${method}" = "HEAD" ]
      then
        total_size_body=$(( total_size_body + size_header ))
      fi
      total_size_body=$(( total_size_body + size_body ))
    done

    [ "${LOG_LEVEL:-0}" -lt 8 ] || {
      local size_response_dump
      size_response_dump="$(wc -c < "$response_dump")"
      local size_header_dump
      size_header_dump="$(wc -c < "$header_dump")"
      LOG_ASYNC='' logging::trace \
        'total size (download): %d = %d' \
        "$(( total_size_header + total_size_body ))" \
        "$(( size_response_dump + size_header_dump ))"
    }
  }
  return "$exit_status"
}

# shellcheck disable=SC2120
function http::default_response() {
  local exit_status="${1:-$?}"
  [ "$exit_status" -eq 22 ] || return "$exit_status"
  cat
}
