#!/bin/false
# shellcheck shell=bash

shopt -s expand_aliases

alias jq='jq -L"$JQ_LIB_DIR" -c'
