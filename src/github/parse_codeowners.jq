split("(\\r?\\n|\\r)"; "") |
map(select((test("^#") or . == "") | not)) |
map(
  gsub("\\\\ "; "\\\b") |
  split("\\s+"; "") |
  map(gsub("[\\b]"; " ")) |
  { pattern: .[0], owners: .[1:] }
)
