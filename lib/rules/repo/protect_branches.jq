import "githublint" as lint;

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
  .repository |
  { location: { url } } as $issue |
  ($pattern.branches // []) as $branches |
  .branches | 
  map(select(.name as $name | $branches | any(. == $name))) |
  map(
    if .protected then
      empty
    else
      $issue + { message: "\(.name) branch is not protected." }
    end
  ) | .[]
;

lint::analyze(analyze; default_configure; $descriptor)
