FROM curlimages/curl
USER root
WORKDIR /root
RUN \
  apk add --no-cache bash nodejs && \
  curl -sSfLo /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x /usr/bin/jq
COPY githublint.sh /root/
COPY lib/ /root/lib/
ENTRYPOINT [ "./githublint.sh" ]
