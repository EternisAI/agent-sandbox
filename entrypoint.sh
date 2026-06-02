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
          "options": {
            "reasoning": { "effort": "high" },
            "provider": {
              "order": ["anthropic"],
              "allow_fallbacks": false
            }
          }
        },
        "anthropic/claude-opus-4.6": {
          "options": {
            "reasoning": { "effort": "high" },
            "provider": {
              "order": ["anthropic"],
              "allow_fallbacks": false
            }
          }
        },
        "anthropic/claude-sonnet-4.6": {
          "options": {
            "reasoning": { "effort": "high" },
            "provider": {
              "order": ["anthropic"],
              "allow_fallbacks": false
            }
          }
        },
        "openai/gpt-5.4": {
          "options": {
            "provider": {
              "order": ["openai"],
              "allow_fallbacks": false
            }
          }
        },
        "openai/gpt-5.4-pro": {
          "options": {
            "provider": {
              "order": ["openai"],
              "allow_fallbacks": false
            }
          }
        },
        "openai/gpt-5.5": {
          "options": {
            "provider": {
              "order": ["openai"],
              "allow_fallbacks": false
            }
          }
        },
        "google/gemini-3.1-pro-preview": {
          "options": { "reasoning": { "effort": "high" } }
        },
        "google/gemini-3.1-flash-lite-preview": {
          "options": { "reasoning": { "effort": "high" } }
        },
        "google/gemini-3.5-flash": {
          "options": { "reasoning": { "effort": "high" } }
        },
        "moonshotai/kimi-k2.6": {},
        "z-ai/glm-5.1": {},
        "deepseek/deepseek-v4-pro": {}
      }
    }
  }
}
EOF

# The backend may supply the agent baseline (axion.md body) per container so it
# can be edited per preset without rebuilding this image. When unset, the
# committed agent/axion.md baked into the image is used unchanged.
if [ -n "$AXION_AGENT_BASELINE" ]; then
  { printf -- '---\nmode: primary\n---\n\n'; printf '%s' "$AXION_AGENT_BASELINE"; } \
    > /home/sandbox/.config/opencode/agent/axion.md
fi

exec opencode serve \
  --hostname 0.0.0.0 \
  --port 4096
