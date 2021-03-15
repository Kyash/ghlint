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
  ) >&2 6>>"$0"
}

function logging::error() {
  logging::log ERROR 31 "$@"
}

function logging::warn() {
  logging::log WARN 35 "$@"
}

function logging::info() {
  logging::log INFO 36 "$@"
}

function logging::debug() {
  if [ ${DEBUG:-0} -ne 0 ]
  then
    logging::log DEBUG 37 "$@"
  fi
}

function logging::trace() {
  if [ ${XTRACE:-0} -ne 0 ]
  then
    logging::log TRACE 34 "$@"
  fi
}
