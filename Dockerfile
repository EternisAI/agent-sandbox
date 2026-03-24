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

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.6.5 --activate

RUN pip install --no-cache-dir uv==0.6.12

RUN npm install -g opencode-ai@1.3.0

ARG TARGETARCH
RUN POLY_VERSION="v0.1.5" && \
    case "${TARGETARCH}" in \
      arm64) POLY_ARCH="aarch64" ;; \
      *)     POLY_ARCH="x86_64" ;; \
    esac && \
    curl -fsSL "https://github.com/Polymarket/polymarket-cli/releases/download/${POLY_VERSION}/polymarket-${POLY_VERSION}-${POLY_ARCH}-unknown-linux-gnu.tar.gz" \
      | tar -xz -C /usr/local/bin polymarket

RUN useradd -m -s /bin/bash sandbox \
    && echo "sandbox ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN mkdir -p /sandbox/.agents /sandbox/workspaces /data \
    && chown -R sandbox:sandbox /sandbox /data

USER sandbox
WORKDIR /sandbox

RUN git config --global user.email "agent@axion.ai" \
    && git config --global user.name "Axion Agent" \
    && git init /sandbox/workspaces

COPY --chown=sandbox:sandbox skills/ /sandbox/.agents/skills/
COPY --chown=sandbox:sandbox entrypoint.sh /sandbox/entrypoint.sh
RUN chmod +x /sandbox/entrypoint.sh && find /sandbox/.agents/skills -name "*.sh" -exec chmod +x {} +

EXPOSE 4096

ENTRYPOINT ["/sandbox/entrypoint.sh"]
