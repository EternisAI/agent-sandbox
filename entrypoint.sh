#!/bin/bash
set -e

: "${PROXY_BASE_URL:?PROXY_BASE_URL is required}"
: "${PROXY_API_KEY:?PROXY_API_KEY is required}"

mkdir -p /data/opencode /data/workspaces
export OPENCODE_DB=/data/opencode/opencode.db

# When a self-hosted backend pins agents to a single model serving name (e.g. a
# vLLM model), operators set LLM_AGENT_MODEL on the backend and it is injected
# into this container as AXION_AGENT_MODEL. OpenCode resolves a model only if it
# is in this provider map or the models.dev catalog, so an arbitrary serving
# name must be declared here or every agent fails with "Model not found:
# openrouter/<name>" before any inference. Declared with empty options so it is
# sent as a plain request. Unset (the Eternis-hosted default) leaves only the
# models baked in below. jq encodes the name as a JSON string key so a value
# containing quotes or backslashes can't corrupt opencode.json.
EXTRA_MODEL_ENTRY=""
if [ -n "$AXION_AGENT_MODEL" ]; then
  EXTRA_MODEL_ENTRY="$(jq -n --arg m "$AXION_AGENT_MODEL" '$m'): {},"
fi

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
        "timeout": 600000,
        "chunkTimeout": 300000
      },
      "models": {
        $EXTRA_MODEL_ENTRY
        "minimax/minimax-m2.5:nitro": {
          "options": {
            "provider": {
              "order": ["mara"],
              "allow_fallbacks": true
            }
          }
        },
        "minimax/minimax-m2.7": {
          "options": {
            "provider": {
              "order": ["mara", "sambanova", "fireworks"],
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
        "moonshotai/kimi-k2.6": {
          "options": {
            "provider": {
              "order": ["parasail", "baidu", "wandb", "moonshotai"],
              "allow_fallbacks": true
            }
          }
        },
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
