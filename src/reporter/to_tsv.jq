def select_repository_columns:
  .owner.login as $org |
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
    (.teams // [] | map("@\($org)/\(.slug):\(.permission)") | join(";")),
    (.codeowners | length > 0),
    (.codeowners // [] | map(.entries | map(.owners)) | flatten | unique | join(" ")),
    (.branches // [] | map(select(.protected)) | map(.name) | join(" "))
  ]
;

def select_organization_columns:
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
;

def select_user_columns:
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
;

def pivot_results($rules; $kind):
  "rules::\({ repository:"repo", organization:"org", user:"org" }[$kind])::" as $prefix |
  . as $results |
  $rules // [] | map(
    .signature as $signature |
    if $signature | startswith($prefix) then
      ($results // []) | map(select(.signature == $signature)) | length == 0
    else
      null
    end
  )
;

(
  if .resources.repositories then
    .resources.repositories | first | select_repository_columns
  elif .resources.organizations then
    .resources.organizations | first | select_organization_columns
  elif .resources.users then
    .resources.users | first | select_organization_columns
  else
    empty
  end
) as $resource_columns |
(
  .results | pivot_results($rules.rules; $resource_columns[0])
) as $results_columns |
$resource_columns + $results_columns | @tsv
