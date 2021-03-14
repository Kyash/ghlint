FROM curlimages/curl as stage0
USER root
RUN \
  apk add --no-cache bash nodejs && \
  curl -sSfLo /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x /usr/bin/jq

FROM stage0 as stage1
USER curl_user
RUN mkdir /home/curl_user/githublint
WORKDIR /home/curl_user/githublint
COPY githublint.sh .
COPY lib/ ./lib/

FROM stage1 as stage2
ENTRYPOINT [ "./githublint.sh" ]
