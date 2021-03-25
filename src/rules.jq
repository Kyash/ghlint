import "githublint" as linter;
import "rule" as rule;

def operate($args):
  $args[0] as $signature |
  $args[1] as $action |
  ($args[2] // "{}" | fromjson) as $configure |
  ("rule" | modulemeta + { $signature } | del(.deps) | linter::describe) as $descriptor |
  if $action == "describe" then
    $descriptor
  else
    linter::analyze(rule::analyze; rule::default_configure + $configure; $descriptor)
  end
;

operate($ARGS.positional)
