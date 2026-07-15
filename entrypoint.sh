#!/bin/bash
set -e

: "${PROXY_BASE_URL:?PROXY_BASE_URL is required}"
: "${PROXY_API_KEY:?PROXY_API_KEY is required}"

mkdir -p /data/opencode /data/workspaces
export OPENCODE_DB=/data/opencode/opencode.db

CONFIG=/home/sandbox/.config/opencode/opencode.json

# Context management (tool-output prune + an auto-compaction backstop) is OFF by
# default and enabled by AXION_AGENT_PRUNE=true, which the backend sets when
# agent inference runs on capacity-constrained self-hosted hardware (i.e. a
# custom, non-OpenRouter agent endpoint). Such deployments need it
# because the agent loop otherwise grows context unbounded — prune is off and the
# self-hosted model has no models.dev window to trigger auto-compaction. Elastic
# upstreams (OpenRouter/Anthropic) don't need it. Prune erases only old completed
# tool-call *outputs* (never reasoning, text, or tool arguments); auto-compaction
# is the lossy summarising backstop, sized so prune keeps it from firing. See
# docs/architecture/capacity-and-admission-control.md in the axionhypothesis repo.
#
# `context` MUST match the serving engine's max_model_len (read from vLLM
# /v1/models); declaring more than the engine serves gets requests rejected at
# the wire once context grows past it — 204800 is the Siam MiniMax-M2.7 window.
#
# `output` is the per-turn generation reserve. 32000 mirrors OpenCode's own
# OUTPUT_TOKEN_MAX constant — the value the runtime already falls back to when a
# model has no output limit — so it both caps a turn's output (via the request's
# maxOutputTokens) and is held back from the window: auto-compaction fires at
# context - output (204800 - 32000 = 172800 here). Because it equals the runtime
# default it is redundant unless lowered, but is kept explicit so the window /
# reserve / threshold are all readable in one place. Override per deployment via
# AXION_AGENT_MODEL_CONTEXT / AXION_AGENT_MODEL_OUTPUT without an image rebuild.
ctx="${AXION_AGENT_MODEL_CONTEXT:-204800}"
out="${AXION_AGENT_MODEL_OUTPUT:-32000}"
# Reject non-numeric overrides (fall back to the default), then force base-10 so
# a zero-padded value like 007 becomes a valid JSON number literal for --argjson
# (leading zeros are not legal JSON and some jq builds reject them).
case "$ctx" in '' | *[!0-9]*) ctx=204800 ;; *) ctx=$((10#$ctx)) ;; esac
case "$out" in '' | *[!0-9]*) out=32000 ;; *) out=$((10#$out)) ;; esac

cat > "$CONFIG" <<EOF
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
        "compatibility": "strict",
        "timeout": 600000,
        "chunkTimeout": 300000
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

# Two post-processing steps, done with jq so they are robust whether the pinned
# model is one of the baked entries above or an arbitrary self-hosted serving
# name (the two must not depend on JSON key ordering or a hand-maintained list):
#
#   1. Declare AXION_AGENT_MODEL if it isn't already baked in, so OpenCode's
#      catalog check passes — an unknown name fails with "Model not found:
#      openrouter/<name>" before any inference. `//= {}` leaves a baked entry
#      (and its reasoning/provider options) untouched and never emits a duplicate
#      key. AXION_AGENT_MODEL is ALWAYS set: the backend defaults thread.agentModel
#      to anthropic/claude-opus-4.6 (baked), so this is a no-op on Eternis-hosted
#      deployments and injects a bare entry only for self-hosted serving names.
#
#   2. When context management is enabled, attach the compaction block and give
#      the pinned model a real window. Setting .limit by path lands it on the
#      right entry whether the model was baked or injected, so it can't be
#      silently dropped by a serving name that collides with a baked slug.
prune=false
[ "$AXION_AGENT_PRUNE" = "true" ] && prune=true
jq \
  --arg m "$AXION_AGENT_MODEL" \
  --argjson prune "$prune" \
  --argjson ctx "$ctx" \
  --argjson out "$out" '
  (if $m != "" then .provider.openrouter.models[$m] //= {} else . end)
  | if $prune then
      .compaction = { auto: true, prune: true }
      | (if $m != "" then .provider.openrouter.models[$m].limit = { context: $ctx, output: $out } else . end)
    else . end
' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"

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
