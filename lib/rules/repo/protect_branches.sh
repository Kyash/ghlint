#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/rules/functions.sh
source "$LIB_DIR/rules/functions.sh"

function rules::repo::protect_branches() {
  test "${1:-}" = "describe" && {
    rules::describe "Protect branches"
    return
  }

  ! jq -ec -L"$JQ_LIB_DIR" \
    --argfile descriptor <(eval "${FUNCNAME[0]}" describe) \
    -f "$LIB_DIR/${FUNCNAME//:://}.jq"
}
