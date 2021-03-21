#!/bin/false
# shellcheck shell=bash

# shellcheck source=../../rules.sh
source "rules.sh"
# shellcheck source=./jq.sh
source "jq.sh"

function rules::repo::protect_branches() {
  test "${1:-}" = "describe" && {
    rules::describe "Protect branches"
    return
  }

  ! jq -e \
    --argfile descriptor <("${FUNCNAME[0]}" describe) \
    -f "${BASH_SOURCE[0]%.*}.jq"
}
