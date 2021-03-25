module {
  name: "CODEOWNERS file exists"
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
  .resource |
  if .codeowners | length > 0 then
    empty
  else
    { message: "CODEOWNERS file does not exist on default branch.", location: { url } }
  end
;
