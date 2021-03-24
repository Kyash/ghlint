#!/bin/false
# shellcheck shell=bash

function rules::list() {
  declare -F | grep '^declare\s\+-fx\?\s\+rules::\(repo\|org\)::' | cut -d' ' -f3
}

function rules::sources() {
  find "${BASH_SOURCE[0]%.*}" -name '*.sh'
}
