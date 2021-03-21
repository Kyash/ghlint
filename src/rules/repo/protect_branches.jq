import "githublint" as lint;

def describe($signature):
  {
    $signature,
    name: "Protect branches"
  }
;

def default_configure:
  {
    patterns: [
      {
        filter: null,
        branches: [.default_branch]
      }
    ]
  }
;

def analyze:
  .pattern as $pattern |
  .resource | 
  { location: { url } } as $issue |
  ($pattern.branches // []) as $branches |
  .branches // [] | 
  map(select(.name as $name | $branches | any(. == $name))) |
  map(
    if .protected then
      empty
    else
      $issue + { message: "\(.name) branch is not protected." }
    end
  ) | .[]
;

$ARGS.positional as $args |
$args[0] as $signature |
$args[1] as $action |
($args[2] // "{}" | fromjson) as $configure |
(describe($signature) | lint::describe) as $descriptor |
if $action == "describe" then
  $descriptor
else
  lint::analyze(analyze; default_configure + $configure; $descriptor)
end
