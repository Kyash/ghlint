#!/usr/bin/env bats

@test "Integration test" {
  command -v docker >/dev/null || skip

  local expected="${GITHUB_REPOSITORY:-Kyash/githublint}"
  local org="${expected%/*}"
  local resulet_file
  resulet_file="$(mktemp)"
  { docker run --rm -e GITHUB_TOKEN -e GITHUBLINT_XTRACE \
    "$(docker build . -q --target stage-prd --file Dockerfile)" \
    -df "select(.full_name == \"$expected\")" "orgs/$org" |
    tee "$resulet_file"
  } || test $? -le 1
  test "$(< "$resulet_file" grep -c '^organization\b')" -eq 1
  test "$(< "$resulet_file" grep '^organization\b' | head -1 | cut -f3)" = "$org"
  test "$(< "$resulet_file" grep -c '^repository\b')" -eq 1
  test "$(< "$resulet_file" grep '^repository\b' | head -1 | cut -f3)" = "$expected"
}
