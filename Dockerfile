FROM curlimages/curl as stage-0
USER root
RUN \
  apk add --no-cache bash nodejs && \
  curl -sSfLo /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x /usr/bin/jq

FROM stage-0 as stage-1
USER curl_user
RUN mkdir -p /home/curl_user/githublint /home/curl_user/.githublint
WORKDIR /home/curl_user/githublint
VOLUME [ "/home/curl_user/.githublint" ]

FROM stage-1 as stage-2
COPY --chown=100 githublint.sh .
COPY --chown=100 lib/ ./lib/

FROM stage-2 as stage-prd
LABEL org.opencontainers.image.source=https://github.com/kyash/githublint
ENTRYPOINT [ "./githublint.sh" ]

FROM stage-1 as stage-dev
USER root
RUN \
  apk add --no-cache git vim && \
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
  )
