#!/bin/false
# shellcheck shell=bash

function function::exists() {
  test "${1:0:1}" != "-" && declare -F "$1" > /dev/null
}

function array::first() {
  echo "${@:1:1}"
}

function array::last() {
  echo "${@:$#:1}"
}
