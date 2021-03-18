#!/bin/false
# shellcheck shell=bash

# shellcheck source=./lib/rules/functions.sh
source "$LIB_DIR/rules/functions.sh"
# shellcheck source=./lib/http.sh
source "$LIB_DIR/http.sh"
# shellcheck source=./lib/jq.sh
source "$LIB_DIR/jq.sh"
# shellcheck source=./lib/github.sh
source "$LIB_DIR/github.sh"

function rules::repo::readme_file_exists() {
  local signature="${FUNCNAME[0]}"
  local opts=( -f "$LIB_DIR/${signature//:://}.jq" --args "${signature}" "$@" )
  if [ "${1}" = "describe" ]
  then
    jq -n "${opts[@]}"
  else
    local resources_dump
    resources_dump="$(mktemp)"
    tee "$resources_dump" | jq -r '.resources.repositories | map([(. | tojson), "\(.url)/readme"] | @tsv) | .[]' |
    while IFS=$'\t' read -r repo url
    do
      { github::fetch "${url}" || { echo 'null' | http::default_response; } } |
        jq -s '[.[1], { readme: .[0] }] | add | { resources: { repositories: [.] } }' \
          <(cat) <(echo "$repo")
    done | {
      ! jq -e "${opts[@]}"
    }
  fi
}
