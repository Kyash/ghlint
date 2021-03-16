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

def parse_cache_index:
  def totime:
    def parse:
      try (strptime("%a, %d %b %Y %H:%M:%S %Z") | mktime) catch null
    ;

    def isnumber:
      if type == "number" then true else try (tonumber | true) catch false end
    ;

    if . == null then
      .
    else
      { string: ., unixtime: (if isnumber then tonumber else parse end) }
    end
  ;

  split("\t") | map(if . == "" then null else . end) |
  {
    url_effective: .[1],
    "last-modified": (.[2] | totime),
    etag: .[3],
    "cache-control": (.[4] | if . == null then . else split(",") | map(ltrimstr(" ")) end),
    pragma: .[5],
    vary: (.[6] | if . == null then . else split(",") | map(ltrimstr(" ")) end),
    expires: (.[7] | totime),
    date: (.[8] | totime),
    file: .[9]
  }
;

def filter_up_to_date_raw_cache_index(filter):
  def _filter:
    parse_cache_index | 
    ([
      .expires.unixtime,
      ((."cache-control" | map(select(test("^max-age=")) | split("=")[1] | tonumber) | max) + .date.unixtime)
    ] | max) as $expires |
    if (filter or $expires > now) then true else (.file | stderr) | false end
  ;

  select(_filter)
;
