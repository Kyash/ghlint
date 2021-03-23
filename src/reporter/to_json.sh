#!/bin/false
# shellcheck shell=bash

# shellcheck source=./src/jq.sh
source "jq.sh"

function reporter::to_json() {
  jq -s '
    def merge($rhs):
      .resources.users |= . + $rhs.resources.users |
      .resources.organizations |= . + $rhs.resources.organizations |
      .resources.repositories |= . + $rhs.resources.repositories |
      .results |= . + $rhs.results
    ;
    reduce .[] as $e ({}; merge($e))
  '
}
