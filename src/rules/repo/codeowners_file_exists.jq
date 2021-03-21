import "githublint" as lint;

def describe($signature):
  {
    $signature,
    name: "CODEOWNERS file exists"
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
  if .codeowners | length > 0 then
    empty
  else
    { message: "CODEOWNERS file does not exist on default branch.", location: { url } }
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
