#!/usr/bin/env bats

setup() {
  load "../src/url.sh"
}

@test "url::parse" {
  local expected="example.com"
  url::parse "http://${expected}/" | jq -e --arg expected "$expected" '.hostname == $expected'
}
