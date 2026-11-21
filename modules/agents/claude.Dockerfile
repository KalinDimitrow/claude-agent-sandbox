# Claude Code, plus the ACP adapter that lets IDEs drive it over stdin/stdout.
ARG PARENT=localhost/sandbox-nodejs
FROM ${PARENT}

USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

ARG NODE_MAJOR=24
RUN if ! command -v npm >/dev/null; then \
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource-setup.sh \
        && bash /tmp/nodesource-setup.sh \
        && rm /tmp/nodesource-setup.sh \
        && apt-get install -y --no-install-recommends nodejs \
        && rm -rf /var/lib/apt/lists/*; \
    fi

ARG ACP_VERSION=0.66.0
RUN npm install -g "@agentclientprotocol/claude-agent-acp@${ACP_VERSION}"

ARG AGENT_USER=agent
USER ${AGENT_USER}

# "stable", "latest", or a pinned version such as 2.1.89.
ARG CLAUDE_VERSION=stable
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh \
    && bash /tmp/claude-install.sh "${CLAUDE_VERSION}" \
    && rm /tmp/claude-install.sh
ENV PATH="/home/${AGENT_USER}/.local/bin:${PATH}"

# Mount point for the claude-config volume; created here so the volume
# inherits the agent user's ownership instead of root's.
RUN mkdir -p "/home/${AGENT_USER}/.claude"
ENV CLAUDE_CONFIG_DIR="/home/${AGENT_USER}/.claude" \
    DISABLE_AUTOUPDATER=1
