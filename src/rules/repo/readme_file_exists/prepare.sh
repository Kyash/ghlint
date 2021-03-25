#!/bin/false
# shellcheck shell=bash

# shellcheck source=./src//http.sh
source "http.sh"
# shellcheck source=./src/jq.sh
source "jq.sh"
# shellcheck source=./src/github.sh
source "github.sh"

function rules::repo::readme_file_exists::prepare() {
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
  done
}
