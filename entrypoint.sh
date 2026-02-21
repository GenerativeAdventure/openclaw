#!/bin/sh
# Fix ownership of /data volume (may be owned by root from a previous deployment)
if [ -d "/data" ]; then
  chown -R node:node /data 2>/dev/null || true
fi

# Ensure config directory exists
STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
chown node:node "$STATE_DIR" 2>/dev/null || true

# Patch gateway config to allow remote control UI access
CONFIG_FILE="$STATE_DIR/openclaw.json"
if [ -f "$CONFIG_FILE" ]; then
  # Use node to safely merge config
  node -e "
    const fs = require('fs');
    const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
    if (!cfg.gateway) cfg.gateway = {};
    if (!cfg.gateway.controlUi) cfg.gateway.controlUi = {};
    cfg.gateway.controlUi.dangerouslyDisableDeviceAuth = true;
    cfg.gateway.controlUi.allowedOrigins = [
      '*',
      'http://localhost', 'http://localhost:3000', 'http://localhost:5173',
      'http://localhost:5500', 'http://localhost:8000', 'http://localhost:8080',
      'https://localhost', 'https://localhost:3000', 'https://localhost:5173',
      'http://127.0.0.1', 'http://127.0.0.1:3000', 'http://127.0.0.1:5173',
      'http://127.0.0.1:5500', 'http://127.0.0.1:8000', 'http://127.0.0.1:8080',
    ];
    fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2));
    console.log('Patched gateway config: disabled device auth, allowed localhost origins');
  " || true
else
  # Create minimal config with control UI settings
  node -e "
    const fs = require('fs');
    const cfg = {
      gateway: {
        controlUi: {
          dangerouslyDisableDeviceAuth: true,
          allowedOrigins: [
            '*',
            'http://localhost', 'http://localhost:3000', 'http://localhost:5173',
            'http://localhost:5500', 'http://localhost:8000', 'http://localhost:8080',
            'https://localhost', 'https://localhost:3000', 'https://localhost:5173',
            'http://127.0.0.1', 'http://127.0.0.1:3000', 'http://127.0.0.1:5173',
            'http://127.0.0.1:5500', 'http://127.0.0.1:8000', 'http://127.0.0.1:8080',
          ]
        }
      }
    };
    fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2));
    console.log('Created gateway config with device auth disabled');
  " || true
  chown node:node "$CONFIG_FILE" 2>/dev/null || true
fi

# Switch to node user and start the gateway
# --bind lan: listen on 0.0.0.0 (required for Railway's proxy)
# --port: use Railway's PORT env var (default 8080)
exec su -s /bin/sh node -c "node /app/openclaw.mjs gateway --allow-unconfigured --bind lan --port ${PORT:-8080}"
