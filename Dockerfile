FROM curlimages/curl as stage-0
USER root
RUN \
  apk add --no-cache bash nodejs && \
  curl -sSfLo /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x /usr/bin/jq
RUN ln -s /usr/local/lib/githublint/main.sh /usr/local/bin/githublint

FROM stage-0 as stage-1
USER curl_user
WORKDIR /home/curl_user
RUN mkdir -p .githublint
VOLUME [ "/home/curl_user/.githublint" ]

FROM stage-1 as stage-deply
COPY src /usr/local/lib/githublint

FROM stage-deply as stage-prd
ARG CREATED
ARG VERSION
ARG REVISION
LABEL \
  org.opencontainers.image.created=${CREATED} \
  org.opencontainers.image.authors= \
  org.opencontainers.image.url= \
  org.opencontainers.image.documentation= \
  org.opencontainers.image.source=https://github.com/kyash/githublint \
  org.opencontainers.image.version=${VERSION} \
  org.opencontainers.image.revision=${REVISION} \
  org.opencontainers.image.vendor="Kyash Inc." \
  org.opencontainers.image.licenses= \
  org.opencontainers.image.title="githublint" \
  org.opencontainers.image.description="Find problems in your GitHub settings." \
  Maintainer= \
  Name= \
  Version= \
  docker.cmd=
ENTRYPOINT [ "githublint" ]

FROM stage-1 as stage-dev
USER root
RUN \
  apk add --no-cache openssh git vim nodejs-npm ncurses && \
  ln -fs /usr/lib/libcurl.so.4.7.0 /usr/lib/libcurl.so.4 && \
  ln -fs /usr/lib/libcurl.so.4 /usr/lib/libcurl.so && \
  curl -sSfL https://raw.githubusercontent.com/reviewdog/reviewdog/master/install.sh | sh -s -- -b /usr/local/bin && \
  ( \
    set -o pipefail && \
    tmpdir="$(mktemp -d)" && \
    cd "$tmpdir" && \
    scversion="stable" && \
    curl -sSfL "https://github.com/koalaman/shellcheck/releases/download/${scversion?}/shellcheck-${scversion?}.linux.x86_64.tar.xz" | \
      tar -xJ "shellcheck-${scversion?}/shellcheck" && \
    mv "shellcheck-${scversion}/shellcheck" /usr/local/bin/ && \
    shellcheck --version && \
    cd && rm -Rf "$tmpdir" \
  ) && \
  npm i -g bats
