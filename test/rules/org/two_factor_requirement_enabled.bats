#!/usr/bin/env bats

setup() {
  PATH="$BATS_TEST_DIRNAME/../../../src:$PATH"
  load "../../../src/rules/org/two_factor_requirement_enabled.sh"
  cd "$(mktemp -d)"
}

@test "rules::org::two_factor_requirement_enabled describe" {
  rules::org::two_factor_requirement_enabled describe |
    jq -e '.signature == "rules::org::two_factor_requirement_enabled"'
}

@test "rules::org::two_factor_requirement_enabled analyze" {
  local configure_dump
  configure_dump="$(mktemp)"
  jq -nr '{}' \
    >"$configure_dump"

  local resources_dump
  resources_dump="$(mktemp)"
  jq -n '{ login: "Kyash", two_factor_requirement_enabled: false }' |
    jq '{ resources: { organizations: [.] } }' \
    >"$resources_dump"

  run rules::org::two_factor_requirement_enabled analyze "$(cat "$configure_dump")" <"$resources_dump"
  declare -p status output >&2 || :
  test "$status" -eq 1
  jq -ne --argjson output "$output" '$output | .signature == "rules::org::two_factor_requirement_enabled"'
}
