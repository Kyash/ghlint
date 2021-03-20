#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/rules/functions.sh
source "rules/functions.sh"
# shellcheck source=./lib/jq.sh
source "jq.sh"

function rules::repo::protect_branches() {
  test "${1:-}" = "describe" && {
    rules::describe "Protect branches"
    return
  }

  ! jq -e \
    --argfile descriptor <("${FUNCNAME[0]}" describe) \
    -f "$LIB_DIR/${FUNCNAME//:://}.jq"
}
