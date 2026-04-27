#!/bin/bash
set -e

: "${PROXY_BASE_URL:?PROXY_BASE_URL is required}"
: "${PROXY_API_KEY:?PROXY_API_KEY is required}"

mkdir -p /data/opencode /data/workspaces
export OPENCODE_DB=/data/opencode/opencode.db

cat > /home/sandbox/.config/opencode/opencode.json <<EOF
{
  "permission": "allow",
  "provider": {
    "openrouter": {
      "npm": "@ai-sdk/openai",
      "name": "OpenRouter",
      "options": {
        "baseURL": "$PROXY_BASE_URL",
        "apiKey": "$PROXY_API_KEY",
        "timeout": 180000,
        "chunkTimeout": 120000
      }
    }
  }
}
EOF

exec opencode serve \
  --hostname 0.0.0.0 \
  --port 4096
