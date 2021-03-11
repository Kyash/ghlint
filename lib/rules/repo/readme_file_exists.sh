source "$LIB_DIR/rules/functions.sh"
source "$LIB_DIR/http.sh"

function rules::repo::readme_file_exists() {
  test "${1:-}" = "describe" && {
    rules::describe "README file exists"
    return
  }

  local url
  url="$(jq -r '.resources.repositories | first | .url')"
  http::request -If "${url}/readme" >/dev/null ||
    { rules::new_issue "README file does not exist on default branch." "$url" && return 1; }
}
