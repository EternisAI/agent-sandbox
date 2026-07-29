FROM python:3.12-slim-bookworm

LABEL org.opencontainers.image.source="https://github.com/EternisAI/agent-sandbox"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    git \
    jq \
    sudo \
    ca-certificates \
    gnupg \
    unzip \
    && rm -rf /var/lib/apt/lists/* \
    && [ -f /usr/bin/bash ] || ln -s /bin/bash /usr/bin/bash

# Pin to a specific Node minor (per project rule: pin all tool versions).
# Keep in sync with .github/workflows/test.yml `node-version` so tests run on
# the same runtime as the production sandbox container. The wildcard pins
# the minor; patches within 24.7 still float — accept that for one minor's
# worth of patch drift in exchange for not having to chase nodesource's
# exact apt version strings on every CI rebuild.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y "nodejs=24.7.*" \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.6.5 --activate

# pyyaml backs plugins/validate_skills.py, which the entrypoint runs before
# `opencode serve` binds. Declared explicitly rather than relied on transitively,
# so an upstream dependency change can't silently disable manifest validation.
RUN pip install --no-cache-dir uv==0.6.12 massive==2.4.0 fredapi==0.5.2 sec-api==1.0.35 pymupdf4llm==1.27.2.2 finnhub-python==2.4.20 pyyaml==6.0.3

# The pinned opencode-ai version fixes which model ids carry real catalog data.
# OpenCode ships an embedded models.dev snapshot and never refreshes it at
# runtime, so a model released after this pin is unknown to it. Declaring such
# an id in entrypoint.sh still makes it usable, which is what makes this easy to
# miss — but it comes back with an empty record: cost 0/0/0/0, so every run on
# it lands $0 in agent_sessions.cost_usd; limit.context 0 and limit.output 0;
# and capabilities.reasoning false, so OpenCode treats it as a model that cannot
# think. Measured on 1.15.5 with a bare "anthropic/claude-opus-5": all of the
# above; on 1.18.9 the same id reports $5/$25, a 1M window, and reasoning true.
# Bumping this pin is therefore part of adding a model, alongside the
# entrypoint.sh declaration. 1.15.5 stopped at claude-opus-4.7; 1.18.9 covers
# through claude-opus-5.
RUN npm install -g opencode-ai@1.18.9 @openrouter/ai-sdk-provider@2.9.0


RUN useradd -m -s /bin/bash sandbox \
    && echo "sandbox ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /sandbox/.agents /sandbox/workspaces /data/opencode /data/workspaces /home/sandbox/.config/opencode \
    && chown -R sandbox:sandbox /sandbox /data /home/sandbox/.config/opencode

USER sandbox
WORKDIR /sandbox

RUN git config --global user.email "agent@axion.ai" \
    && git config --global user.name "Axion Agent" \
    && git init /sandbox/workspaces

COPY --chown=sandbox:sandbox skills/ /home/sandbox/.agents/skills/
COPY --chown=sandbox:sandbox plugins/ /home/sandbox/.config/opencode/plugins/
COPY --chown=sandbox:sandbox agent/ /home/sandbox/.config/opencode/agent/
COPY --chown=sandbox:sandbox entrypoint.sh /sandbox/entrypoint.sh
RUN chmod +x /sandbox/entrypoint.sh && find /home/sandbox/.agents/skills -name "*.sh" -o -name "*.py" | xargs chmod +x

EXPOSE 4096

ENTRYPOINT ["/sandbox/entrypoint.sh"]
