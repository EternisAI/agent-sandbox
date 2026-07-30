#!/bin/bash
# Fail if any model entrypoint.sh declares would run without catalog data under
# the pinned opencode-ai version.
#
# Why this is worth a CI step: declaring an id the pinned models.dev snapshot
# does not know is not an error. OpenCode accepts it and serves it with an empty
# record — cost 0 for input, output and both cache legs, limit.context 0,
# limit.output 0, capabilities.reasoning false. Agents on that model then run
# fine, bill $0 into agent_sessions.cost_usd, get no context window, and are
# treated as unable to reason. Nothing in a boot log or a thread says so. That
# is what happened to anthropic/claude-opus-5 under the 1.15.5 pin.
#
# So the invariant is: a model added to the backend's coordinatorVariants.agents
# gets declared here AND has to be covered by the pin. This checks the second
# half by reading back what OpenCode itself resolves each declared id to. Run it
# inside a built image, where the pinned runtime lives:
#
#   docker run --rm -v "$PWD/scripts:/scripts:ro" --entrypoint bash \
#     agent-sandbox:ci /scripts/check-model-catalog.sh
set -euo pipefail

CONFIG=/home/sandbox/.config/opencode/opencode.json

# Generate the config the way a real boot does, rather than parsing the heredoc
# out of entrypoint.sh — the jq post-processing steps are part of what ships.
# The stub stands in for `opencode serve` on the last line so the script exits
# instead of binding a port. It has to be torn off PATH before the real
# `opencode` runs below.
stub="$(mktemp -d)"
printf '#!/bin/sh\nexit 0\n' > "$stub/opencode"
chmod +x "$stub/opencode"
env PROXY_BASE_URL="http://127.0.0.1:1/unused" \
    PROXY_API_KEY="unused" \
    PATH="$stub:$PATH" \
    /sandbox/entrypoint.sh
rm -rf "$stub"

resolved="$(mktemp)"
opencode models --verbose > "$resolved"

python3 - "$CONFIG" "$resolved" <<'PY'
import json, sys

config_path, resolved_path = sys.argv[1], sys.argv[2]

# Ids that legitimately resolve to nothing. glm-5.2-fast is the name the backend
# coined for Baseten's low-variance GLM-5.2 tier; it has no OpenRouter listing
# to look up, which is why entrypoint.sh gives it an explicit cost block. It
# still gets no window, and that is accepted: those deployments run with
# AXION_AGENT_PRUNE=true, where the entrypoint sets .limit itself.
ALLOWLIST = {"z-ai/glm-5.2-fast"}

declared = json.load(open(config_path))["provider"]["openrouter"]["models"]

# `opencode models --verbose` prints "<provider>/<id>" then a pretty-printed
# JSON object closing on a bare "}" at column zero.
resolved, header, buf = {}, None, []
for line in open(resolved_path):
    if line.startswith("{"):
        buf = [line]
    elif buf:
        buf.append(line)
        if line.rstrip("\n") == "}":
            record = json.loads("".join(buf))
            resolved[(record["providerID"], record["id"])] = record
            buf = []

failed = []
for model_id in sorted(declared):
    if model_id in ALLOWLIST:
        continue
    record = resolved.get(("openrouter", model_id))
    if record is None:
        failed.append((model_id, "OpenCode does not resolve it at all"))
        continue
    if not record.get("cost", {}).get("input"):
        failed.append((model_id, "costs 0 per token, so agent spend on it records as $0"))
    elif not record.get("limit", {}).get("context"):
        failed.append((model_id, "has no context window"))

for model_id, reason in failed:
    print(f"{model_id}: {reason}")

if failed:
    print()
    print("These ids are not in the models.dev snapshot the pinned opencode-ai")
    print("ships. Bump the pin in the Dockerfile so the catalog covers them, drop")
    print("the declaration if nothing offers the model any more, or add it to")
    print("ALLOWLIST here with a comment saying why it has no catalog record.")
    sys.exit(1)

print(f"all {len(declared)} declared models resolve with catalog data")
PY
