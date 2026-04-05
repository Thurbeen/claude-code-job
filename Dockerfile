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

RUN npm install -g @anthropic-ai/claude-code

COPY scripts/ /usr/local/share/claude-code-job/scripts/
RUN chmod +x /usr/local/share/claude-code-job/scripts/*.sh

RUN mkdir -p /workspace \
    && chown node:node /workspace

USER node
WORKDIR /workspace

ENTRYPOINT ["/bin/bash"]
