#!/bin/false
# shellcheck shell=bash

function logging::log() {
  (
    set +x
    local level="$1"
    local color="$2"
    shift 2

    flock 6
    printf '\e[%sm[%s]\t' "$color" "$level"
    if [ $# -ne 0 ]
    then
      printf "$@"
    else
      cat
    fi | {
      sed -e "s/\b${GITHUB_TOKEN}\b/$(eval printf x"%.s" "{1..${#GITHUB_TOKEN}}")/g"
    }
    printf '\e[m\n'
  ) >&2 6>>"$0" &
}

function logging::error() {
  if [ ${LOG_LEVEL:-0} -ge 3 ]
  then
    logging::log ERROR 31 "$@"
  fi
}

function logging::warn() {
  if [ ${LOG_LEVEL:-0} -ge 4 ]
  then
    logging::log WARN 35 "$@"
  fi
}

function logging::info() {
  if [ ${LOG_LEVEL:-0} -ge 6 ]
  then
    logging::log INFO 36 "$@"
  fi
}

function logging::debug() {
  if [ ${LOG_LEVEL:-0} -ge 7 ]
  then
    logging::log DEBUG 37 "$@"
  fi
}

function logging::trace() {
  if [ ${LOG_LEVEL:-0} -ge 8 ]
  then
    logging::log TRACE 34 "$@"
  fi
}
