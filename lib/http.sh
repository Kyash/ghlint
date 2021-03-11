source "${LIB_DIR}/logging.sh"

function http::configure_curlrc() {
  echo "$@"
}

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
    http::head "$@" | jq -rc '.[]' | while read line; do logging::trace '%s' "$line"; done
    http::request "$@" -X GET -L | jq -c | logging::trace
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
