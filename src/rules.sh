#!/bin/false
# shellcheck shell=bash

# shellcheck source=./src/functions.sh
source "functions.sh"
# shellcheck source=./src/jq.sh
source "jq.sh"

function rules::list() {
  declare -F | grep '^declare\s\+-fx\?\s\+rules::\(repo\|org\)::' | grep -v '::prepare$' | cut -d' ' -f3
}

function rules::operate() {
  local rule_dir="$1"
  shift
  local signature="${FUNCNAME[1]}"
  local opts=( -L "$rule_dir" -f "${BASH_SOURCE[0]%.*}.jq" --args "${signature}" "$@" )

  if [ "${1}" = "describe" ]
  then
    jq -n "${opts[@]}"
    return
  fi

  local prepare_funcname="${signature}::prepare"
  if function::exists "$prepare_funcname"
  then
    "$prepare_funcname" "$@"
  else
    cat
  fi |
  if jq -e "${opts[@]}"
  then
    return 1
  else
    local exit_status="$?"
    [ "$exit_status" -eq 4 ] || return "$exit_status";
  fi
}

function rules::declare() {
  local base_dir="${BASH_SOURCE[0]%/*}"
  while IFS= read -r rule_file
  do
    local rule_dir="${rule_file%/rule.jq}"
    local relative_rule_dir="${rule_dir#${base_dir}/}"
    local rule_funcname="${relative_rule_dir////::}"
    local prepare_shell_file="${rule_dir}/prepare.sh"
    # shellcheck source=/dev/null
    ! [ -f "$prepare_shell_file" ] || source "$prepare_shell_file"
    eval "function $rule_funcname () { rules::operate '$rule_dir' \"\$@\"; }"
  done < <(find "${base_dir}/rules" -name 'rule.jq')
}
