module {
  name: "Two-factor requirement enabled",
  severity: "High",
  confidence: "High"
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
  if .two_factor_requirement_enabled then
    empty
  elif .two_factor_requirement_enabled == null then
    { message: "\"Require two-factor authentication for everyone in your organization\" is unknown.", confidence: "Unknown", location: { url } }
  else
    { message: "\"Require two-factor authentication for everyone in your organization\" is disabled.", location: { url } }
  end
;
