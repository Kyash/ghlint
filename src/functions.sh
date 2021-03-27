#!/bin/false
# shellcheck shell=bash

function function::exists() {
  [ "${1:0:1}" != "-" ] && ! [[ "$1" =~ = ]] && declare -F "$1" > /dev/null
}

function function:passthrough() {
  return "$1"
}

function function::callback() {
  local job_pids=()
  while IFS= read -r callback
  do
    "$callback" "$@" &
    job_pids+=("$!")
  done

  local exit_status="$1"
  for pid in "${job_pids[@]}"
  do
    local callbacked_status=0
    wait "$pid" || callbacked_status="$?"
    [ "$callbacked_status" -eq "$1" ] || exit_status="$callbacked_status"
  done
  return "$exit_status"
}

function array::first() {
  echo "${@:1:1}"
}

function array::last() {
  echo "${@:$#:1}"
}

function array::includes() {
  local usage="usage: ${FUNCNAME[0]} -e PATTERN... [-i INDEX] VALUE..."
  local patterns=()
  local index=1
  OPTIND=1
  while getopts 'e:i:' OPT
  do
    case "$OPT" in
      e) patterns+=(-e "$OPTARG") ;;
      i) index=$(( OPTARG + 1 )) ;;
      *) echo "$usage" >&2 && exit 1 ;;
    esac
  done
  shift $((OPTIND - 1))
  [ "${#patterns[@]}" -gt 0 ] || { echo "$usage" >&2 && exit 1; }

  printf '%s\n' "${@:$index}" | grep -qx "${patterns[@]}"
}

function stream::slice() {
  local offset="${1:-0}"
  local length="${2:--0}"
  local ignore_sigpipe="${3:-}"
  {
    if [ "$offset" -eq 0 ]
    then
      cat
    else 
      tail -c +"$offset"
    fi || {
      local exit_status="$?"
      [ "$exit_status" -eq 141 ] || return "$exit_status"
      if [ -n "$ignore_sigpipe" ]
      then
        logging::debug '%s function caught SIGPIPE (status: %d).' "${FUNCNAME[0]}" "$exit_status"
        return "$exit_status"
      else
        logging::debug '%s function ignored SIGPIPE.' "${FUNCNAME[0]}"
      fi
    }
  } | head -c "$length"
}

function crypto::hash() {
  md5sum | cut -d' ' -f1
}

function process::count_running_jobs() {
  jobs -pr | wc -l
}
