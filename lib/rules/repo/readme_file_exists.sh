#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/rules/functions.sh
source "$LIB_DIR/rules/functions.sh"
# shellcheck source=./lib/http.sh
source "$LIB_DIR/http.sh"

function rules::repo::readme_file_exists() {
  test "${1:-}" = "describe" && {
    rules::describe "README file exists"
    return
  }

  jq -r '.resources.repositories | first | .url' | {
    IFS= read -r url
    github::fetch -I "${url}/readme" >/dev/null ||
      { rules::new_issue "README file does not exist on default branch." "$url" && return 1; }
  }
}
