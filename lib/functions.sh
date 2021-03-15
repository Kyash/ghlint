#!/bin/false
# shellcheck shell=bash

function function::exists() {
  [ "${1:0:1}" != "-" ] && ! [[ "$1" =~ = ]] && declare -F "$1" > /dev/null
}

function function:passthrough() {
  return "$1"
}

function array::first() {
  echo "${@:1:1}"
}

function array::last() {
  echo "${@:$#:1}"
}

function stream::slice() {
  local offset="${1:-0}"
  local length="${2:--0}"
  tail -c +"$offset" | head -c "$length"
}
