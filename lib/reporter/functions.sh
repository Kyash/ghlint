#!/bin/false
# shellcheck shell=bash

function reporter::list() {
  declare -F | grep '^declare\s\+-fx\?\s\+reporter::to_' | cut -d' ' -f3
}
