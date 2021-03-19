#!/bin/bash

set -ueo pipefail

declare -r DOCKERFILE="${DOCKERFILE:-Dockerfile}"
declare -r BUILD_OPTS=(--target stage-dev --file "$DOCKERFILE")
declare -r CONTAINER_NAME="${CONTAINER_NAME:-githublint_dev_env}"

function finally () {
  docker stop "$CONTAINER_NAME"
}

function main() {
  local container_id
  container_id="$(docker ps -aqf name="$CONTAINER_NAME")"
  if [ -z "$container_id" ]
  then
    docker build . "${BUILD_OPTS[@]}"
    docker run -itd --name "$CONTAINER_NAME" -e GITHUB_TOKEN \
      -v "$PWD:/home/curl_user/githublint" \
      -v "$HOME/.gitconfig:/home/curl_user/.gitconfig" \
      -v "$HOME/.ssh:/home/curl_user/.ssh" \
      -w "/home/curl_user/githublint" \
      -u curl_user \
      "$(docker build . -q "${BUILD_OPTS[@]}")" \
      bash
  fi
  docker start "$CONTAINER_NAME"
  trap finally EXIT
  docker exec -it "$CONTAINER_NAME" bash
}

main "$@"
