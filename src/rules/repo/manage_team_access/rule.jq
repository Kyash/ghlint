module {
  name: "Manage team access",
  severity: "High",
  confidence: "Low"
};

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
  .resource |
  { location: { url } } as $issue |
  if .teams == null then
    $issue + { message: "Teams is unknown", confidence: "Unknown" }
  else
    .teams | map({ slug, permission }) |
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
  end
;
