#!/usr/bin/env bats

setup() {
  PATH="$BATS_TEST_DIRNAME/../../../src:$PATH"
  load "../../../src/rules.sh"
  rules::declare
  cd "$(mktemp -d)"
}

@test "rules::repo::protect_branches describe" {
  rules::repo::protect_branches describe |
    jq -e '.signature == "rules::repo::protect_branches"'
}

@test "rules::repo::protect_branches analyze" {
  local configure_dump
  configure_dump="$(mktemp)"
  jq -nr '{}' \
    >"$configure_dump"

  local resources_dump
  resources_dump="$(mktemp)"
  jq -n '{ allow_force_pushes: { enabled: true } }' |
  jq '{ name: "ghlint", default_branch: "main", branches: [ { name: "main", protected: true, protection: . } ] }' |
    jq '{ resources: { repositories: [.] } }' \
    >"$resources_dump"

  run rules::repo::protect_branches analyze "$(cat "$configure_dump")" <"$resources_dump"
  declare -p status output >&2 || :
  test "$status" -eq 1
  jq -ne --argjson output "$output" '$output | .signature == "rules::repo::protect_branches"'
}
