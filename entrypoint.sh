#!/bin/bash
set -e

: "${PROXY_BASE_URL:?PROXY_BASE_URL is required}"
: "${PROXY_API_KEY:?PROXY_API_KEY is required}"

mkdir -p /data/opencode /data/workspaces
export OPENCODE_DB=/data/opencode/opencode.db

cat > /home/sandbox/.config/opencode/opencode.json <<EOF
{
  "permission": "allow",
  "default_agent": "axion",
  "provider": {
    "openrouter": {
      "npm": "@openrouter/ai-sdk-provider",
      "name": "OpenRouter",
      "options": {
        "baseURL": "$PROXY_BASE_URL",
        "apiKey": "$PROXY_API_KEY",
        "timeout": 180000,
        "chunkTimeout": 120000
      },
      "models": {
        "minimax/minimax-m2.5:nitro": {
          "options": {
            "provider": {
              "order": ["mara"],
              "allow_fallbacks": true
            }
          }
        },
        "anthropic/claude-opus-4.7": {
          "options": { "reasoning": { "effort": "high" } }
        },
        "anthropic/claude-opus-4.6": {
          "options": { "reasoning": { "effort": "high" } }
        },
        "anthropic/claude-sonnet-4.6": {
          "options": { "reasoning": { "effort": "high" } }
        }
      }
    }
  }
}
EOF

exec opencode serve \
  --hostname 0.0.0.0 \
  --port 4096
