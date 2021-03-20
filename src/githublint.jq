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
  .resources.repositories | .[] |
  . as $repository |
  (run_control($descriptor.signature | split("::"))) // default_configure |
  .patterns // [] |
  map(select(
    .filter // {} | to_entries | map(.value as $regex | $repository[.key] | test($regex)) | all
  )) |
  map({ $repository, pattern: . } | process | new_issue($descriptor)) | .[]
;
