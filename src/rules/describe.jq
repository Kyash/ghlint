$ARGS.positional |
{
  $signature,
  name: .[0],
  description: .[1],
  severity: (.[2] // "Low"),
  confidence: (.[3] // "Low"),
  help: .[4],
  tags: (.[5] // "[]" | fromjson)
}
