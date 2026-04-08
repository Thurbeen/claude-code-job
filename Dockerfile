FROM node:24-bookworm

# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=v4.45.4

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      curl \
      jq \
      ripgrep \
      fd-find \
      fzf \
      openssh-client \
      python3 \
      python3-venv \
      build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
      -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.32.3

RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# Install uv (Python package manager) for MCP servers that use uvx
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

RUN npm install -g @anthropic-ai/claude-code

# Force cache invalidation for scripts
ARG SCRIPTS_CACHE_BUST=1
COPY scripts/ /usr/local/share/claude-code-job/scripts/
RUN find /usr/local/share/claude-code-job/scripts -name '*.sh' -exec chmod +x {} +

COPY skills/ /usr/local/share/claude-code-job/skills/

RUN mkdir -p /workspace \
    && chown node:node /workspace

USER node
WORKDIR /workspace

ENTRYPOINT ["/bin/bash"]
