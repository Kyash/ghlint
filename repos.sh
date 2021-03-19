#!/bin/bash

set -ue

declare -r VERSION="${VERSION:-latest}"
declare -r IMANGE="${IMANGE:-}"
declare -r DOCKERFILE="${DOCKERFILE:-Dockerfile}"
declare -r BUILD_OPTS=(--target stage-prd --file "$DOCKERFILE")
declare -r CONTAINER_NAME="githublint_$$"

function finally () {
  docker stop "$CONTAINER_NAME"
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

  {
    docker run --name "$CONTAINER_NAME" --rm -e GITHUB_TOKEN \
      -v "$PWD/.githublintrc.json:/home/curl_user/githublint/.githublintrc.json" \
      --mount "type=volume,src=githublint,dst=/home/curl_user/.githublint" \
      "$image" \
      "$@" \
      2>&1 1>&3 3>&- | {
        awk '{print strftime("%Y-%m-%dT%H:%M:%S%z") "\t" $0}'
      }
  } 3>&1 1>&2 | grep '^\(kind\|repository\)\t' | cut -f2-
}

main "$@"
