import ".githublintrc" as $rc;

def log(l; f):
  . as $o | (f | l) | $o
;

def new_issue($descriptor):
  $descriptor + . | { signature, severity, confidence, message, location }
;

def run_control($path):
  $rc::rc | first | getpath($path)
;

def describe:
  if has("signature") and has("name") then
    {
      description: null,
      severity: "Low",
      confidence: "Low",
      help: null,
      tags: []
    } + .
  else
    "Rule descriptor is invalid!" | halt_error(2)
  end
;

def analyze(process; default_configure; $descriptor):
  (run_control($descriptor.signature | split("::"))) as $configure |
  ($configure.kind // "repositories") as $kind |
  .resources[$kind] // [] | .[] |. as $resource |
  ($configure // default_configure).patterns // [] |
  map(select(
    .filter // {} | to_entries | map(.value as $regex | $resource[.key] // "" | test($regex)) | all
  )) |
  map({ $resource, pattern: . } | process | new_issue($descriptor)) | .[]
;
