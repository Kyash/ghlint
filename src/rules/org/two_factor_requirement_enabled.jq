import "githublint" as lint;

def describe($signature):
  {
    $signature,
    name: "Two-factor requirement enabled",
    severity: "High",
    confidence: "High"
  }
;

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

$ARGS.positional as $args |
$args[0] as $signature |
$args[1] as $action |
($args[2] // "{}" | fromjson) as $configure |
(describe($signature) | lint::describe) as $descriptor |
if $action == "describe" then
  $descriptor
else
  lint::analyze(analyze; default_configure + $configure; $descriptor)
end
