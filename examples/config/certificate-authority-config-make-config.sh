#!/bin/bash

RANDOM_KEY=$(hexdump -n 16 -e "4/4 \"%08X\" 1 \"\n\"" /dev/random);

# This assumes that this config map is mounted in /scripts folder.
cat /scripts/config-template.json |
sed "s/%%%AUTH_KEY%%%/${AUTH_KEY}/g" |
sed "s/%%%RANDOM_KEY%%%/${RANDOM_KEY}/g" |
sed "s/%%%EXPIRY_CLIENT_HOURS%%%/${EXPIRY_CLIENT_HOURS}/g" |
sed "s/%%%EXPIRY_SERVER_HOURS%%%/${EXPIRY_SERVER_HOURS}/g" > /config/config.json;
