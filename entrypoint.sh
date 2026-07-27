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

# OpenRouter streaming timeouts (milliseconds). chunk_timeout is the max gap
# between streamed chunks; the self-hosted reasoning model (MiniMax M2.7) can go
# quiet for minutes mid-turn while reasoning, tripping the old 5m gap timeout and
# forcing needless agent respawns. Bumped to 8m. req_timeout is the whole-request
# ceiling. Override per deployment via AXION_AGENT_STREAM_CHUNK_TIMEOUT_MS /
# AXION_AGENT_STREAM_TIMEOUT_MS without an image rebuild. Same numeric guard as
# ctx/out above (reject non-numeric, force base-10 for a valid JSON literal).
chunk_timeout="${AXION_AGENT_STREAM_CHUNK_TIMEOUT_MS:-480000}"
req_timeout="${AXION_AGENT_STREAM_TIMEOUT_MS:-600000}"
case "$chunk_timeout" in '' | *[!0-9]*) chunk_timeout=480000 ;; *) chunk_timeout=$((10#$chunk_timeout)) ;; esac
case "$req_timeout" in '' | *[!0-9]*) req_timeout=600000 ;; *) req_timeout=$((10#$req_timeout)) ;; esac

# MCP tool-call timeout (milliseconds). This global default is the ONLY timeout
# knob that reaches the MCP servers the backend registers, and it registers all
# of them dynamically over the McpAdd API. OpenCode resolves a tool call's
# timeout as `cfg.mcp[server].timeout ?? cfg.experimental.mcp_timeout`
# (packages/opencode/src/mcp/index.ts, MCP.tools()), and `cfg.mcp` is the
# *on-disk* config only — a server added at runtime never appears there. So the
# per-server timeout the backend sends with McpAdd is stored on the client and
# used for connect/list, but never applied to a tool call: every dynamically
# registered server silently falls back to the MCP SDK's 60s default. Observed
# on Siam as exa_deep_research failing `-32001 Request timed out` at 60.03s on
# calls whose own budget is 6m, making that tool structurally unable to finish.
#
# 420000 matches exaMCPTimeoutMs in the backend and exceeds exa's own
# agentRunMaxWait (6m), so the handler's deadline fires first and this stays a
# backstop rather than the primary bound. That layering holds because every MCP
# the backend registers bounds its own work server-side: exa 6m (30s per HTTP
# call), firecrawl 30s, news 30s, mediawiki 30s (whole agent loop), youtube 100s
# per request. A third-party MCP that does *not* self-bound will now hold a tool
# slot for up to 7m instead of 60s — that is the trade for deep_research working
# at all, and the reason to keep this overridable per deployment via
# AXION_AGENT_MCP_TIMEOUT_MS. Same numeric guard as ctx/out above.
mcp_timeout="${AXION_AGENT_MCP_TIMEOUT_MS:-420000}"
case "$mcp_timeout" in '' | *[!0-9]*) mcp_timeout=420000 ;; *) mcp_timeout=$((10#$mcp_timeout)) ;; esac
# Unlike ctx/out, this key is schema-typed PositiveInt, so a literal 0 is not
# merely useless but rejected at config load — which would wedge the sandbox on
# boot rather than degrade it. Guard the one value the digit test lets through.
[ "$mcp_timeout" -gt 0 ] || mcp_timeout=420000

# Models carrying per-model options are declared below; the rest resolve from
# models.dev. "z-ai/glm-5.2-fast" is neither — it is the id the backend coined
# for Baseten's low-variance GLM-5.2 tier, which has no OpenRouter listing to
# resolve against, so it MUST stay declared here. Drop it and every agent on
# that model dies at getModel with ProviderModelNotFoundError, surfacing as a
# "completed" agent that echoed its prompt.
#
# The three z-ai ids also carry explicit "cost" (USD per 1M tokens): the backend
# proxy rewrites them onto Baseten's own GLM endpoints, but OpenCode still prices
# every assistant message from the models.dev catalog, which lists OpenRouter's
# rates — or, for glm-5.2-fast, nothing at all, which prices the run at zero.
# That number is what lands in agent_sessions.cost_usd, so without these blocks
# agent spend on Baseten is silently wrong. Rates from Baseten's own
# /v1/models; re-check them when the served tiers change.
cat > "$CONFIG" <<EOF
{
  "permission": "allow",
  "default_agent": "axion",
  "experimental": {
    "mcp_timeout": $mcp_timeout
  },
  "provider": {
    "openrouter": {
      "npm": "@openrouter/ai-sdk-provider",
      "name": "OpenRouter",
      "options": {
        "baseURL": "$PROXY_BASE_URL",
        "apiKey": "$PROXY_API_KEY",
        "compatibility": "strict",
        "timeout": $req_timeout,
        "chunkTimeout": $chunk_timeout
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
        "z-ai/glm-5.1": {
          "cost": { "input": 1.30, "output": 4.30, "cache_read": 0.26 }
        },
        "z-ai/glm-5.2": {
          "cost": { "input": 1.40, "output": 4.40, "cache_read": 0.14 }
        },
        "z-ai/glm-5.2-fast": {
          "cost": { "input": 2.10, "output": 6.60, "cache_read": 0.21 }
        },
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

# Validate the skill manifests before serving. OpenCode discovers a skill by
# parsing its SKILL.md YAML frontmatter and drops any manifest that fails to
# parse — silently, with no log line at all. Its retry path does not save such a
# file either: gray-matter caches the failed parse keyed on the file contents,
# so the sanitized-retry fallback runs only for the first parse in the process
# and every later one (OpenCode rescans skills per agent *worktree*) returns
# empty data without throwing. A manifest whose YAML is invalid therefore loads
# for the first agent in a sandbox and vanishes for every agent after it. That
# is how thai-government-data came to never once load on Siam while the
# entrypoint's old line-regex validator reported it present.
#
# So this runs the repo's manifest contract (plugins/validate_skills.py — the
# same checker CI runs with --strict) over the baked skills: real YAML parse,
# required keys, name == directory, ${CLAUDE_SKILL_DIR} paths resolve. Any
# violation is logged as WARN skill-validation instead of being silently absent.
# Reading every SKILL.md also primes the page cache before `opencode serve`
# binds (the worker only dispatches after health-probing that HTTP endpoint, so
# this necessarily completes first). The loaded count is written to a readiness
# marker that is invalidated up front and replaced atomically only after a clean
# scan, so an aborted run never leaves a stale count advertising readiness.
#
# Best-effort on purpose: a bad optional skill must not wedge the sandbox, so a
# violation is logged and startup continues. CI is where a broken manifest
# blocks — see plugins/skill-manifests.test.js.
SKILLS_READY_FILE="${SKILLS_READY_FILE:-/tmp/.skills-ready}"
python3 /home/sandbox/.config/opencode/plugins/validate_skills.py \
  --marker "$SKILLS_READY_FILE" \
  /home/sandbox/.agents/skills \
  /home/sandbox/.claude/skills || true

exec opencode serve \
  --hostname 0.0.0.0 \
  --port 4096
