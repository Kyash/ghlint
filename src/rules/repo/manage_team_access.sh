#!/bin/false
# shellcheck shell=bash

# shellcheck source=../../rules.sh
source "rules.sh"
# shellcheck source=./jq.sh
source "jq.sh"

function rules::repo::manage_team_access() {
  test "${1:-}" = "describe" && {
    rules::describe "Manage team access"
    return
  }

  ! jq -e \
    --argfile descriptor <("${FUNCNAME[0]}" describe) \
    -f "${BASH_SOURCE[0]%.*}.jq"
}
