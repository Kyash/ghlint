#!/usr/bin/env bats

setup() {
  PATH="$BATS_TEST_DIRNAME/../../../src:$PATH"
  load "../../../src/rules.sh"
  rules::declare
  cd "$(mktemp -d)"
}

@test "rules::repo::manage_team_access describe" {
  rules::repo::manage_team_access describe |
    jq -e '.signature == "rules::repo::manage_team_access"'
}

@test "rules::repo::manage_team_access analyze" {
  local configure_dump
  configure_dump="$(mktemp)"
  jq -nr '{ patterns: [ { filter: null, allowlist: [ { slug: "foo", permission: "push" } ] } ] }' \
    >"$configure_dump"

  local resources_dump
  resources_dump="$(mktemp)"
  jq -n '{ name: "ghlint", teams: [ { slug: "bar", permission: "push" } ] }' |
    jq '{ resources: { repositories: [.] } }' \
    >"$resources_dump"

  run rules::repo::manage_team_access analyze "$(cat "$configure_dump")" <"$resources_dump"
  declare -p status output >&2 || :
  test "$status" -eq 1
  jq -ne --argjson output "$output" '$output | .signature == "rules::repo::manage_team_access"'
}
