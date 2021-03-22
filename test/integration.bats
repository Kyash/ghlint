#!/usr/bin/env bats

@test "Integration test" {
  command -v docker >/dev/null || skip

  expected="${GITHUB_REPOSITORY:-Kyash/githublint}"
  resulet_file="$(mktemp)"
  { docker run --rm -e GITHUB_TOKEN -e GITHUBLINT_XTRACE \
    "$(docker build . -q --target stage-prd --file Dockerfile)" \
    -df "map(select(.full_name == \"$expected\"))" orgs/Kyash | tee "$resulet_file"; } ||
    test $? -le 1
  actual="$(< "$resulet_file" grep '^repository\b' | head -1 | cut -f3)"
  test "$actual" = "$expected"
}
