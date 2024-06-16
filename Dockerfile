FROM  alpine:3.20

# Same effect as the example above but using 3 commands
RUN apk update \
    && apk add jq \
    && apk add --no-cache bash \
    && rm -rf /var/cache/apk

copy gitmagic.sh /app/gitmagic.sh

RUN chmod +x /app/gitmagic.sh

# Define the command to run the script
CMD [ "/app/gitmagic.sh" ]