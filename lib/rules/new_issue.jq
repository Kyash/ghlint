import "githublint" as lint;

$ARGS.positional |
{
  message: .[0],
  location: { url: .[1] },
  severity: .[3],
  confidence: .[4]
} | to_entries | map(select(.value != null)) | from_entries |
lint::new_issue($descriptor)
