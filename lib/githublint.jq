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

def analyze(process; default_configure; $descriptor):
  .resources.repositories | first |
  . as $repository |
  (run_control($descriptor.signature | split("::"))) // default_configure |
  .patterns + [] |
  map(select(
    .filter // {} | to_entries | map(.value as $regex | $repository[.key] | test($regex)) | all
  )) |
  map({ $repository, pattern: . } | process | new_issue($descriptor)) | .[]
;
