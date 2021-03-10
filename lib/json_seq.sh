function json_seq::new() {
  printf '\x1e'
  if [ $# -ne 0 ]
  then
    jq -sc 'add' "$@"
  else
    jq -c
  fi
}
