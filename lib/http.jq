def parse_header:
  index(":") as $pos |
  if $pos then
    .[0:$pos] as $key |
    (.[$pos + 1:] | ltrimstr(" ")) as $value |
    { ($key): $value }
  else
    .
  end
;

def merge_headers:
  map(to_entries) |
  reduce .[] as $headers ({}; reduce ($headers | .[]) as $header (.; .[$header.key] += [$header.value] )) |
  to_entries | map({ key, value: .value | join(",") }) | from_entries
;

def parse_headers:
  split("\r\n") |
  map(parse_header) |
  reduce .[] as $e ([]; if ($e | type) == "string" then (.[0] += $e) else (.[1] += [$e]) end) |
  [.[0], (.[1] | merge_headers)]
;

def parse_link_header:
  split(",") |
  map(
    split(";") | map(ltrimstr(" ")) |
    ([ ({ key: "href", value: (.[0] | gsub("(^<|>$)"; "")) }) ]) +
    (.[1:] | map(split("=") | { key : (.[0]), value: (.[1] | gsub("(^\"|\"$)"; "")) })) | from_entries
  )
;
