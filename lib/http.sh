function http::configure_curlrc() {
  test -e "$HOME/.curlrc" && cat < "$HOME/.curlrc"
  echo "$@"
}

function http::parse_header() {
  node "$LIB_DIR/parse_header.js" "$@"
}

function http::request() {
  curl -K "$CURLRC" "$@"
}

function http::list() {
  local url="$1"
  shift
  local num_of_pages
  num_of_pages=$(
    http::request -I "${url}" "$@" |
      http::parse_header |
      jq -r '
      map(select(.link?)) |
      map(.link | map(select(.rel == "last")) | map(.href.searchParams.page)) |
      flatten | first // empty
      '
  )
  params="$(if [ -n "${num_of_pages}" ]; then printf 'page=[1-%d]' "${num_of_pages}"; fi)"
  http::request "${url}?${params}" "$@"
}
