#!/bin/false
# shellcheck shell=bash

# shellcheck source=../../rules.sh
source "rules.sh"
# shellcheck source=./jq.sh
source "jq.sh"

function rules::repo::manage_team_access() {
  local signature="${FUNCNAME[0]}"
  local opts=( -f "${BASH_SOURCE[0]%.*}.jq" --args "${signature}" "$@" )
  if [ "${1}" = "describe" ]
  then
    jq -n "${opts[@]}"
  else
    ! jq -e "${opts[@]}"
  fi
}
