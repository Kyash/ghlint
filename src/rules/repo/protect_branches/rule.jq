module {
  name: "Protect branches"
};

def default_configure:
  {
    patterns: [
      {
        filter: null,
        branches: [.default_branch],
        standards: {
          "allow_force_pushes": {
            "enabled": false
          },
          "allow_deletions": {
            "enabled": false
          }
        }
      }
    ]
  }
;

def matches($standards):
  delpaths([ path(..) | select(contains(["url"])) ]) as $rules |
  $standards | to_entries | all(.value as $value | $rules[.key] | if . == null then false else contains($value) end)
;

def analyze:
  .pattern as $pattern |
  .resource |
  { location: { url } } as $issue |
  .branches // [] |
  map(select(.name as $name | $pattern.branches // [] | any(. == $name))) |
  map(
    if .protected then
      if .protection == null then
        $issue + { message: "The rules for the \(.name) branch are unknown.", confidence: "Unknown" }
      elif .protection | matches($pattern.standards) then
        empty
      else
        $issue + { message: "The rules of the \(.name) branch do not meet the standards of the organization." }
      end
    else
      $issue + { message: "\(.name) branch is not protected." }
    end
  ) | .[]
;
