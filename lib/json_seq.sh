function json_seq::new() {
  printf '\x1e'
  if [ $# -ne 0 ]
  then
    local filter='add'
    if [ $XTRACE -ne 0 ]
    then
      echo "$@" | xargs -L 1 jq -c '.'
      filter='def log(logger;f):. as $o|(f|logger)|$o;log(debug;{length:(length),types:(map(type)),test:(add)})|'$filter
    fi >&2
    jq -sc "$filter" "$@"
  else
    jq -c
  fi
}
