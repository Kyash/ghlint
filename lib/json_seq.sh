function json_seq::new() {
  printf '\x1e'
  if [ $# -ne 0 ]
  then
    local filter='add'
    jq -sc "$filter" "$@"
  else
    jq -c
  fi
}
