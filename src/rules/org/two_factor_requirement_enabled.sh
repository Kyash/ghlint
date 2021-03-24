#!/bin/false
# shellcheck shell=bash

# shellcheck source=./src/rules.sh
source "rules.sh"
# shellcheck source=./src/jq.sh
source "jq.sh"

function rules::org::two_factor_requirement_enabled() {
  local signature="${FUNCNAME[0]}"
  local opts=( -f "${BASH_SOURCE[0]%.*}.jq" --args "${signature}" "$@" )
  if [ "${1}" = "describe" ]
  then
    jq -n "${opts[@]}"
  else
    if jq -e "${opts[@]}"
    then
      return 1
    else
      local exit_status="$?"
      [ "$exit_status" -eq 4 ] || return "$exit_status";
    fi
  fi
}
