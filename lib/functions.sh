function function::exists() {
  declare -F $1 > /dev/null
}

function array::first() {
  echo "${@:1:1}"
}

function array::last() {
  echo "${@:$#:1}"
}
