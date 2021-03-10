(
  if .resources.repositories
  then
    .resources.repositories|first|
    [
      "repository",
      .id,
      .full_name,
      .default_branch,
      .private,
      .description,
      .fork,
      .language,
      .archived,
      .disabled,
      .created_at,
      (.stats.commit_activity | length as $l | if $l == 0 then 0 else map(.total) | add / $l end),
      (.teams | map("@\($org)/\(.slug):\(.permission)")|join(";")),
      (.codeowners | length > 0),
      (.codeowners | map(.entries|map(.owners)) | flatten | unique | join(" ")),
      (.branches | map(select(.protected)) | map(.name) | join(" "))
    ]
  elif .resources.organizations
  then
    .resources.organizations|first|
    [
      "organization",
      .id,
      .login,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      .created_at,
      null,
      null,
      null,
      null,
      null
    ]
  elif .resources.users
  then
    .resources.users|first|
    [
      "user",
      .id,
      .login,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      .created_at,
      null,
      null,
      null,
      null,
      null
    ]
  else
    empty
  end
) + (
  .results as $results |
  $rules.rules | map(
    .signature as $signature |
    $results | map(select(.signature == $signature)) | length == 0
  )
)
| @tsv
