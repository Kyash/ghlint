function json_seq::new() {
  printf '\x1e'
  if [ $# -ne 0 ]
  then
    if [ $XTRACE -ne 0 ]
    then
      echo "$@" | xargs -L 1 jq -c '.'
    fi >&2
    jq -sc 'add' "$@"
  else
    jq -c
  fi
}
