source "$LIB_DIR/rules/functions.sh"

function rules::repo::codeowners_file_exists() {
  test "${1:-}" = "describe" && {
    rules::describe "CODEOWNERS file exists"
    return
  }

  ! jq -ec -L"$JQ_LIB_DIR" \
    --argfile descriptor <(eval "$FUNCNAME" describe) \
    -f "$LIB_DIR/${FUNCNAME//:://}.jq"
}