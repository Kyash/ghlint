function rules::list() {
  declare -F | grep '^declare\s\+-fx\?\s\+rules::\(repo\|org\)::' | cut -d' ' -f3
}

function rules::new_issue() {
  local signature="${FUNCNAME[1]}"
  jq -nc -L"$JQ_LIB_DIR" \
    --argfile descriptor <(eval "$signature" describe) \
    --args \
    -f "$LIB_DIR/${FUNCNAME//:://}.jq" "$@"
}

function rules::describe() {
  jq -nc --arg signature "${FUNCNAME[1]}" --args -f "$LIB_DIR/${FUNCNAME//:://}.jq" "$@"
}
