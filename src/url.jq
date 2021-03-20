def tostring:
  def _join($delimiter):
    map(select(. != "")) | join($delimiter)
  ;

  . as $o |
  ($o.searchParams | to_entries | map(@uri "\(.key)=\(.value)")| join("&")) as $query |
  ([$o.username, $o.password] | _join(":") | [., $o.hostname] | _join("@") | [., $o.port] | _join(":")) as $host |
  ["\($o.protocol)//\($host)\($o.pathname)", $query] | _join("?") | [., $o.hash] | _join("#")
;
