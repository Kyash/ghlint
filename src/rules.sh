#!/bin/false
# shellcheck shell=bash

# shellcheck source=./src/jq.sh
source "jq.sh"

function rules::list() {
  declare -F | grep '^declare\s\+-fx\?\s\+rules::\(repo\|org\)::' | cut -d' ' -f3
}

function rules::sources() {
  find "${BASH_SOURCE[0]%.*}" -name '*.sh'
}

function rules::new_issue() {
  local signature="${FUNCNAME[1]}"
  jq -n -f "${BASH_SOURCE[0]%.*}/${FUNCNAME[0]##*::}.jq" --args "$signature" "$@"
}

function rules::describe() {
  jq -n --arg signature "${FUNCNAME[1]}" --args -f "${BASH_SOURCE[0]%.*}/${FUNCNAME[0]##*::}.jq" "$@"
}
