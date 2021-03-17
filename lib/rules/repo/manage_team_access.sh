#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/rules/functions.sh
source "$LIB_DIR/rules/functions.sh"

function rules::repo::manage_team_access() {
  test "${1:-}" = "describe" && {
    rules::describe "Manage team access"
    return
  }

  ! jq -ec -L"$JQ_LIB_DIR" \
    --argfile descriptor <("${FUNCNAME[0]}" describe) \
    -f "$LIB_DIR/${FUNCNAME//:://}.jq"
}
