#!/bin/false
# shellcheck shell=bash

shopt -s expand_aliases

# shellcheck disable=SC2139
alias jq='jq -L"'"$(dirname "${BASH_SOURCE[0]}")"'" -c'
