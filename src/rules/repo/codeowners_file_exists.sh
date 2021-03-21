#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/rules/functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../functions.sh"
# shellcheck source=./lib/jq.sh
source "jq.sh"

function rules::repo::codeowners_file_exists() {
  local signature="${FUNCNAME[0]}"
  local opts=( -f "${BASH_SOURCE[0]%.*}.jq" --args "${signature}" "$@" )
  if [ "${1}" = "describe" ]
  then
    jq -n "${opts[@]}"
  else
    ! jq -e "${opts[@]}"
  fi
}