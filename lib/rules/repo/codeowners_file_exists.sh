#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/rules/functions.sh
source "$LIB_DIR/rules/functions.sh"
# shellcheck source=./lib/jq.sh
source "$LIB_DIR/jq.sh"

function rules::repo::codeowners_file_exists() {
  local signature="${FUNCNAME[0]}"
  local opts=( -f "$LIB_DIR/${signature//:://}.jq" --args "${signature}" "$@" )
  if [ "${1}" = "describe" ]
  then
    jq -n "${opts[@]}"
  else
    ! jq -e "${opts[@]}"
  fi
}
