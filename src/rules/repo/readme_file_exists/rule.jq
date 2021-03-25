module {
  name: "README file exists"
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
  if .readme then
    empty
  else
    { message: "README file does not exist on default branch.", location: { url } }
  end
;
