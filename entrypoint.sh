#!/bin/sh
# Fix ownership of /data volume (may be owned by root from a previous deployment)
if [ -d "/data" ]; then
  chown -R node:node /data 2>/dev/null || true
fi

# Switch to node user and start the gateway
exec su -s /bin/sh node -c "node /app/openclaw.mjs gateway --allow-unconfigured --bind lan"
