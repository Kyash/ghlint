#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/jq.sh
source "$LIB_DIR/jq.sh"

function rules::list() {
  declare -F | grep '^declare\s\+-fx\?\s\+rules::\(repo\|org\)::' | cut -d' ' -f3
}

function rules::new_issue() {
  local signature="${FUNCNAME[1]}"
  jq -n -f "$LIB_DIR/${FUNCNAME//:://}.jq" --args "$signature" "$@"
}

function rules::describe() {
  jq -n --arg signature "${FUNCNAME[1]}" --args -f "$LIB_DIR/${FUNCNAME//:://}.jq" "$@"
}
