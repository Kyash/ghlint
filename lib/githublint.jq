import ".githublintrc" as $rc;

def new_issue($descriptor):
  $descriptor + . | { signature, severity, confidence, message, location }
;

def run_control($key):
  $rc::rc | first | .[$key]
;

def analyze(process; default_configure; $descriptor):
  .resources.repositories | first |
  . as $repository |
  (run_control($descriptor.signature)) // default_configure |
  .patterns + [] | map(select(.filter as $filter | $repository.full_name | test($filter))) |
  map({ $repository, pattern: . } | process | new_issue($descriptor)) | .[]
;
