#!/bin/bash

set -ue

declare -r VERSION="${VERSION:-latest}"
declare -r IMANGE="${IMANGE:-}"
declare -r DOCKERFILE="${DOCKERFILE:-Dockerfile}"
declare -r BUILD_OPTS=(--target stage-prd --file "$DOCKERFILE")
declare -r CONTAINER_NAME="githublint_$$"

function finally () {
  docker ps -qf "name=$CONTAINER_NAME" | while IFS= read -r container_id
  do
    docker stop "$container_id"
  done
}

function main() {
  trap finally EXIT

  local image="docker.pkg.github.com/kyash/githublint/githublint:${VERSION}"
  if [ -n "$IMANGE" ]
  then
    image="$IMANGE"
  elif [ -f "$DOCKERFILE" ]
  then
    image="$(docker build . -q "${BUILD_OPTS[@]}")"
  fi

  docker run --name "$CONTAINER_NAME" --rm -e GITHUB_TOKEN \
    -v "$PWD/.githublintrc.json:/home/curl_user/.githublintrc.json" \
    --mount "type=volume,src=githublint,dst=/home/curl_user/.githublint" \
    "$image" "$@" |
    grep '^\(kind\|repository\)\t' | cut -f2-
}

main "$@"
