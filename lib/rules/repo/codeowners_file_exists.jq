import "githublint" as lint;

def default_configure:
  {
    patterns: [
      {
        filter: ".*"
      }
    ]
  }
;

def analyze:
  .repository |
  if .codeowners | length > 0 then
    empty
  else
    { message: "CODEOWNERS file does not exist on default branch.", location: { url } }
  end
;

lint::analyze(analyze; default_configure; $descriptor)
