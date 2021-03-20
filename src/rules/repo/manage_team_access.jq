import "githublint" as lint;

def default_configure:
  {}
;

def analyze:
  .pattern as $pattern |
  .repository |
  { location: { url } } as $issue |
  .teams | map({ slug, permission }) |
  (
    ($pattern.allowlist | map({ slug, permission })) as $allowlist |
    if contains($allowlist) then
      empty
    else
      $issue + { message: "Contains teams that should be allowed access" }
    end
  ),
  (
    ($pattern.denylist | map({ slug, permission })) as $denylist |
    if any(. as $team | $denylist | any(. == $team)) then
      $issue + { message: "Contains teams that should be denied access" }
    else
      empty
    end
  )
;

lint::analyze(analyze; default_configure; $descriptor)
