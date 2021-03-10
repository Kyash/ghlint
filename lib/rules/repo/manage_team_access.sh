source "$LIB_DIR/rules/functions.sh"

function rules::repo::manage_team_access() {
  test "${1:-}" = "describe" && {
    rules::describe "Manage team access"
    return
  }

  ! jq -ec -L"$JQ_LIB_DIR" \
    --argfile descriptor <(eval "$FUNCNAME" describe) \
    -f "$LIB_DIR/${FUNCNAME//:://}.jq"
}
