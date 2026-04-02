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

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@10.6.5 --activate

RUN pip install --no-cache-dir uv==0.6.12 massive==2.4.0

RUN npm install -g opencode-ai@1.3.2

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

RUN mkdir -p /sandbox/.agents /sandbox/workspaces /data/opencode /data/workspaces /home/sandbox/.config/opencode \
    && chown -R sandbox:sandbox /sandbox /data /home/sandbox/.config/opencode

USER sandbox
WORKDIR /sandbox

RUN git config --global user.email "agent@axion.ai" \
    && git config --global user.name "Axion Agent" \
    && git init /sandbox/workspaces

COPY --chown=sandbox:sandbox skills/ /home/sandbox/.agents/skills/
COPY --chown=sandbox:sandbox entrypoint.sh /sandbox/entrypoint.sh
RUN chmod +x /sandbox/entrypoint.sh && find /home/sandbox/.agents/skills -name "*.sh" -o -name "*.py" | xargs chmod +x

EXPOSE 4096

ENTRYPOINT ["/sandbox/entrypoint.sh"]
