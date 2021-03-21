import "githublint" as lint;

def describe($signature):
  {
    $signature,
    name: "Manage team access"
  }
;

def default_configure:
  {
    patterns: [
      {
        filter: null
      }
    ]
  }
;

def analyze:
  .pattern as $pattern |
  .repository |
  { location: { url } } as $issue |
  .teams // [] | map({ slug, permission }) |
  (
    ($pattern.allowlist // [] | map({ slug, permission })) as $allowlist |
    if contains($allowlist) then
      empty
    else
      $issue + { message: "Contains teams that should be allowed access" }
    end
  ),
  (
    ($pattern.denylist // [] | map({ slug, permission })) as $denylist |
    if any(. as $team | $denylist | any(. == $team)) then
      $issue + { message: "Contains teams that should be denied access" }
    else
      empty
    end
  )
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
