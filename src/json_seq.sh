#!/bin/false
# shellcheck shell=bash

# shellcheck source=./src/jq.sh
source "jq.sh"

function json_seq::new() {
  printf '\x1e'
  jq -s "add" "$@"
}
