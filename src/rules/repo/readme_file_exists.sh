#!/bin/false
# shellcheck shell=bash

# shellcheck source=./src//http.sh
source "http.sh"
# shellcheck source=./src/jq.sh
source "jq.sh"
# shellcheck source=./src/github.sh
source "github.sh"

function rules::repo::readme_file_exists() {
  local signature="${FUNCNAME[0]}"
  local opts=( -f "${BASH_SOURCE[0]%.*}.jq" --args "${signature}" "$@" )
  if [ "${1}" = "describe" ]
  then
    jq -n "${opts[@]}"
  else
    local resources_dump
    resources_dump="$(mktemp)"
    tee "$resources_dump" | jq -r '.resources.repositories | map([(. | tojson), "\(.url)/readme"] | @tsv) | .[]' |
    while IFS=$'\t' read -r repo url
    do
      {
        github::fetch "${url}" || {
          local exit_status="$?"
          echo 'null' | http::default_response "$exit_status"
        }
      } |
        jq -s '[.[0], { readme: .[1] }] | add | { resources: { repositories: [.] } }' \
          <(echo "$repo") <(cat)
    done |
      if jq -e "${opts[@]}"
      then
        return 1
      else
        local exit_status="$?"
        [ "$exit_status" -eq 4 ] || return "$exit_status";
      fi
  fi
}
