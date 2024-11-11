FROM  alpine:3.20

# Same effect as the example above but using 3 commands
RUN apk update \
    && apk add jq \
    && apk add --no-cache bash \
    && rm -rf /var/cache/apk

COPY gitmagic.sh /usr/local/bin/gitmagic
RUN chmod +x /usr/local/bin/gitmagic

# Make the gitmagic command available globally
ENV PATH="/usr/local/bin:${PATH}"