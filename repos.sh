#!/bin/bash

set -ue

declare -r VERSION="${VERSION:-latest}"
declare -r IMANGE="${IMANGE:-}"
declare -r DOCKERFILE="${DOCKERFILE:-Dockerfile}"
declare -r BUILD_OPTS=(--target stage-prd --file "$DOCKERFILE")
declare -r CONTAINER_NAME="githublint_$$"

function finally () {
  command -v docker /dev/null || return
  docker ps -qf "name=$CONTAINER_NAME" | while IFS= read -r container_id
  do
    docker stop "$container_id"
  done
}

function main() {
  trap finally EXIT

  local default_rc_file="$PWD/.githublintrc.json"
  local rc_file=''
  ! [ -f "$default_rc_file" ] || rc_file="$default_rc_file"

  local args=()
  while getopts ":c:de:f:hp:r:x" OPT
  do
    case "$OPT" in
      c) rc_file="$OPTARG" ;;
      e | f | p | r) args+=("-$OPT" "$OPTARG") ;;
      d | x | h) args+=("-$OPT") ;;
      ?) args+=("-$OPTARG") ;;
    esac
  done
  shift $((OPTIND - 1))
  args+=("$@")

  local image="docker.pkg.github.com/kyash/githublint/githublint:${VERSION}"
  if [ -n "$IMANGE" ]
  then
    image="$IMANGE"
  elif [ -f "$DOCKERFILE" ]
  then
    image="$(docker build . -q "${BUILD_OPTS[@]}")"
  fi

  docker_run_opts=()
  [ "${rc_file:0:1}" = '/' ] || rc_file="$PWD/$rc_file"
  [ -z "$rc_file" ] || docker_run_opts+=(-v "$rc_file:/home/curl_user/.githublintrc.json")

  docker run --name "$CONTAINER_NAME" --rm -e GITHUB_TOKEN \
    --mount "type=volume,src=githublint,dst=/home/curl_user/.githublint" \
    "${docker_run_opts[@]+"${docker_run_opts[@]}"}" \
    "$image" "${args[@]+"${args[@]}"}"
}

main "$@"
