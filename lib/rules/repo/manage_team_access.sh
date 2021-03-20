#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/rules/functions.sh
source "rules/functions.sh"
# shellcheck source=./lib/jq.sh
source "jq.sh"

function rules::repo::manage_team_access() {
  test "${1:-}" = "describe" && {
    rules::describe "Manage team access"
    return
  }

  ! jq -e \
    --argfile descriptor <("${FUNCNAME[0]}" describe) \
    -f "$LIB_DIR/${FUNCNAME//:://}.jq"
}
