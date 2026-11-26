#!/bin/bash
# Let's Encrypt sertifikası yenilenince LiveKit'in okuyabileceği dizine kopyalar.
# Tetiklenme: certbot renew → /etc/letsencrypt/renewal-hooks/deploy/
DOMAIN=$(basename "$RENEWED_LINEAGE")
if [[ "$DOMAIN" == live-staging* || "$DOMAIN" == stream* ]]; then
    cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /project/teqlif/config/ssl/${DOMAIN}-fullchain.pem
    cp /etc/letsencrypt/live/$DOMAIN/privkey.pem   /project/teqlif/config/ssl/${DOMAIN}-privkey.pem
    chown tucibeyin:tucibeyin /project/teqlif/config/ssl/${DOMAIN}-*.pem
    chmod 600 /project/teqlif/config/ssl/${DOMAIN}-privkey.pem
fi
