#!/bin/bash
set -e

: "${OPENROUTER_BASE_URL:?OPENROUTER_BASE_URL is required}"
: "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY is required}"

mkdir -p /sandbox/.agents
cat > /sandbox/.agents/opencode.json <<EOF
{
  "provider": {
    "openrouter": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "OpenRouter",
      "options": {
        "baseURL": "$OPENROUTER_BASE_URL",
        "apiKey": "$OPENROUTER_API_KEY"
      }
    }
  }
}
EOF

exec opencode serve \
  --hostname 0.0.0.0 \
  --port 4096
