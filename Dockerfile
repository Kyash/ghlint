FROM node
RUN curl -sSfLo /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && chmod +x /usr/bin/jq
COPY githublint.sh /root/
COPY lib/ /root/lib/
WORKDIR /root
ENTRYPOINT [ "./githublint.sh" ]
