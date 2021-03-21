#!/bin/false
# shellcheck shell=bash

# shellcheck disable=SC2120
function url::parse() {
  node "${BASH_SOURCE[0]%.*}/${FUNCNAME[0]##*::}.js" "$@"
}
