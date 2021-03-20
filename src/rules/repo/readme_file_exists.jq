import "githublint" as lint;

def describe($signature):
  {
    $signature,
    name: "README file exists"
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
  .repository |
  if .readme then
    empty
  else
    { message: "README file does not exist on default branch.", location: { url } }
  end
;

$ARGS.positional as $args |
$args[0] as $signature |
$args[1] as $action |
(describe($signature) | lint::describe) as $descriptor |
if $action == "describe" then
  $descriptor
else
  lint::analyze(analyze; default_configure; $descriptor)
end
