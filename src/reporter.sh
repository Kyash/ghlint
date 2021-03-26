#!/bin/false
# shellcheck shell=bash

function reporter::list() {
  declare -F | grep '^declare\s\+-fx\?\s\+reporter::to_' | cut -d' ' -f3
}

function reporter::sources() {
  find "${BASH_SOURCE[0]%.*}" -name '*.sh'
}

function reporter::declare() {
  sources_file="$(mktemp)"
  reporter::sources | while read -r file
  do
    echo source "$file"
  done > "$sources_file"
  # shellcheck source=/dev/null
  source "$sources_file"
}
