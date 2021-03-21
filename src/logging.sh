#!/bin/false
# shellcheck shell=bash

declare -p LOG_LOCK_FILE &>/dev/null || {
  LOG_LOCK_FILE="$(mktemp)"
  declare -r LOG_LOCK_FILE
}
declare LOG_ASYNC="${LOG_ASYNC:-}"
declare LOG_LEVEL="${LOG_LEVEL:-6}"

function logging::log() {
  {
    set +x
    set -ue
    local level="$1"
    local color="$2"
    local prefix="$3"
    shift 3

    local timestamp
    timestamp="$(date -Iseconds)"

    flock 6
    printf '%s\t\e[%sm[%s]\t%s' "$timestamp" "$color" "$level" "$prefix"
    if [ $# -ne 0 ]
    then
      # shellcheck disable=SC2059
      printf "$@"
    else
      cat
    fi | {
      sed -e "s/\b${GITHUB_TOKEN}\b/$(eval printf x"%.s" "{1..${#GITHUB_TOKEN}}")/g"
    }
    printf '\e[m\n'
  } >&2 6>>"$LOG_LOCK_FILE" &
  [ -n "$LOG_ASYNC" ] || wait "$!"
}

function logging::error() {
  [ "${LOG_LEVEL:-0}" -lt 3 ] || logging::log ERROR 31 '' "$@"
}

function logging::warn() {
  [ "${LOG_LEVEL:-0}" -lt 4 ] || logging::log WARN 35 '' "$@"
}

function logging::info() {
  [ "${LOG_LEVEL:-0}" -lt 6 ] || logging::log INFO 36 '' "$@"
}

function logging::debug() {
  [ "${LOG_LEVEL:-0}" -lt 7 ] || logging::log DEBUG 37 '' "$@"
}

function logging::trace() {
  local prefix
  prefix="$(printf '%s:%d%s | ' "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "${FUNCNAME[1]:+ - ${FUNCNAME[1]}()}")"
  [ "${LOG_LEVEL:-0}" -lt 8 ] || logging::log TRACE 34 "$prefix" "$@"
}
