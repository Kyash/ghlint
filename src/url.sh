#!/bin/false
# shellcheck shell=bash

# shellcheck disable=SC2120
function url::parse() {
  node "$LIB_DIR/parse_url.js" "$@"
}
