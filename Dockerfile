FROM curlimages/curl as stage0
USER root
RUN \
  apk add --no-cache bash nodejs && \
  curl -sSfLo /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x /usr/bin/jq

FROM stage0 as stage1
USER curl_user
RUN mkdir -p /home/curl_user/githublint /home/curl_user/.githublint
WORKDIR /home/curl_user/githublint
VOLUME [ "/home/curl_user/.githublint" ]

FROM stage1 as stage2
COPY --chown=100 githublint.sh .
COPY --chown=100 lib/ ./lib/

FROM stage2 as stage3
ENTRYPOINT [ "./githublint.sh" ]
