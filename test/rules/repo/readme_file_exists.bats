#!/usr/bin/env bats

setup() {
  PATH="$BATS_TEST_DIRNAME/../../../src:$PATH"
  load "../../../src/rules/repo/readme_file_exists.sh"
  cd "$(mktemp -d)"
  function github::fetch() {
    return 22
  }
}

@test "rules::repo::readme_file_exists describe" {
  rules::repo::readme_file_exists describe |
    jq -e '.signature == "rules::repo::readme_file_exists"'
}

@test "rules::repo::readme_file_exists analyze" {
  local configure_dump
  configure_dump="$(mktemp)"
  jq -nr '{}' \
    >"$configure_dump"

  local resources_dump
  resources_dump="$(mktemp)"
  jq -n '{ name: "githublint", url: "https://api.github.com/repos/Kyash/githublint" }' |
    jq '{ resources: { repositories: [.] } }' \
    >"$resources_dump"

  run rules::repo::readme_file_exists analyze "$(cat "$configure_dump")" <"$resources_dump"
  declare -p status output >&2 || :
  test "$status" -eq 1
  jq -ne --argjson output "$output" '$output | .signature == "rules::repo::readme_file_exists"'
}
