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
function http::parse_url() {
  node "$LIB_DIR/parse_url.js" "$@"
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

  if [ "${XTRACE:-0}" -ne 0 ]
  then
    declare -p exit_status response_dump header_dump stat_dump args callback | while IFS= read -r line
    do
      logging::trace '%s' "$line"
    done
  fi

  local functions=(
    http::callback_store_cache
    "$callback"
  )
  for func in "${functions[@]}"
  do
    "$func" "$exit_status" "$response_dump" "$header_dump" "$stat_dump" "$@"
  done
  return
}

function http::clean_cache() {
  local dumps=()
  dumps+=("$(mktemp)")
  dumps+=("$(mktemp)")
  local new_cache_index_file="${dumps[0]}"
  local outdated_files="${dumps[1]}"
  {
    flock -s 6
    jq -L"$JQ_LIB_DIR" -Rcr 'import "http" as http; http::filter_up_to_date_cache_index(http::parse_cache_index; ."last-modified")' \
      >"$new_cache_index_file" 2>"$outdated_files"
    flock -x 6
    cat <"$new_cache_index_file" >"$CACHE_INDEX_FILE"
    logging::debug '%s' "Updated cache index file."
  } 6>>"$CACHE_INDEX_FILE" <"$CACHE_INDEX_FILE"

  jq -r < "$outdated_files" | {
    local count=0
    while IFS= read -r file
    do
      if [ -f "$file" ]
      then
        rm "$file"
      fi
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
    jq -L"$JQ_LIB_DIR" -Rc 'import "http" as http; http::parse_cache_index' |
    jq -escr --arg url "$url_effective" \
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
  jq -scr 'map([.stat.http_code, .stat.url_effective] | @tsv) | .[]' < "$stat_dump" | {
    while IFS=$'\t' read -r http_code url_effective
    do
      if [ "$http_code" = "304" ]
      then
        {
          flock -s 6
          http::find_cache "$url_effective" | http::respond_from_cache &&
            logging::debug 'Respond from the cache instead of %s' "$url_effective"
        } 6>>"$CACHE_INDEX_FILE" <"$CACHE_INDEX_FILE" || return 24
      fi
    done
  }
  return "$exit_status"
}

function http::callback_sleep_when_rate_limit_is_exceeded() {
  local exit_status="$1"
  local response_dump="$2"
  local header_dump="$3"
  local stat_dump="$4"
  local args=("${@:5}")
  jq -scr 'map([.stat.http_code, .stat.size_download, .stat.size_header, .stat.url_effective] | @tsv) | .[]' < "$stat_dump" | {
    local total_size_header=0
    local total_size_body=0
    while IFS=$'\t' read -r http_code size_body size_header url_effective
    do
      if [ "${http_code:0:1}" = "4" ]
      then
        stream::slice "$total_size_header" "$size_header" < "$header_dump" | {
          jq -L"$JQ_LIB_DIR" -Rscr \
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
  } | jq -scr 'max // empty' | {
    IFS= read -r sleep_time || :
    logging::trace 'sleep time %d' "${sleep_time:-0}"
    if [ "${sleep_time:-0}" -gt 0 ]
    then
      local now
      now="$(date +%s)"
      local rest_time=$((now + sleep_time))
      logging::warn \
        'Wait %d seconds because the rate limit has been exceeded. Expected to resume in %s' \
        "$sleep_time" "$(date --date "@$rest_time")"
      sleep $(("$sleep_time" + 5))
      return 20
    fi
  }
  return "$exit_status"
}

function http::callback_store_cache() {
  local exit_status="$1"
  local response_dump="$2"
  local header_dump="$3"
  local stat_dump="$4"
  local args=("${@:5}")
  test "$exit_status" -eq 0 || return
  jq -escr 'map([.exitcode, .stat.http_code, .stat.method, .stat.size_download, .stat.size_header, .stat.url_effective] | @tsv) | .[]' "$stat_dump" | {
    local total_size_header=0
    local total_size_body=0
    while IFS=$'\t' read -r exitcode http_code method size_body size_header url_effective
    do
      logging::trace '%d,%d,%s,%d,%d,%s' "$exitcode" "$http_code" "$method" "$size_body" "$size_header" "$url_effective"
      if [ "$exitcode" -eq 0 ] && [ "${method}" != "HEAD" ] && [ "${http_code:0:1}" = '2' ] && [ "${http_code}" != '204' ]
      then
        stream::slice "$total_size_header" "$size_header" < "$header_dump" | {
          jq -L"$JQ_LIB_DIR" -Rscr \
            --arg url_effective "$url_effective" \
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
            local cache_file="$CACHE_DIR/$cache_filename"
            {
              flock 6
              if [ ! -e "$cache_file" ]
              then
                touch "$cache_file"
                stream::slice "$total_size_body" "$size_body" < "$response_dump" > "$cache_file"
                printf '%s\t%s\t%s\t%s\t%s\n' "$index" "$entry" "$expires" "$date" "$cache_file" >>"$CACHE_INDEX_FILE"
              fi
            } 6>>"$CACHE_INDEX_FILE"
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

    if [ "${XTRACE:-0}" -ne 0 ]
    then
      local size_response_dump
      size_response_dump="$(wc -c < "$response_dump")"
      local size_header_dump
      size_header_dump="$(wc -c < "$header_dump")"
      logging::trace \
        'total size (download): %d = %d' \
        "$(( total_size_header + total_size_body ))" \
        "$(( size_response_dump + size_header_dump ))"
    fi
  }
}
