function reporter::to_tsv() {
  local org="$ORG"
  local rules_dump="$1"

  local fields=(
    kind
    id
    full_name
    default_branch
    private
    description
    fork
    language
    archived
    disabled
    created_at
    commit_activity
    teams
    exists_codeowners
    codeowners
    protected_branches
  )
  jq -r --args '$ARGS.positional + (.rules | map(.signature)) | @tsv' "${fields[@]}" < "$rules_dump"

  jq --seq -r --arg org "$org" --argfile rules "$rules_dump" -f "$LIB_DIR/${FUNCNAME//:://}.jq"
}