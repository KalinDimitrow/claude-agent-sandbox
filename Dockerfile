# Agent container: Claude Code as a non-root user, no extra capabilities.
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships a default "ubuntu" user at UID 1000; replace it so the
# container user can match your host UID (avoids permission problems on the
# mounted project). Build with: HOST_UID=$(id -u) docker compose build
ARG HOST_UID=1000
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -u "${HOST_UID}" -s /bin/bash claude \
    && mkdir -p /home/claude/.claude /workspace \
    && chown -R claude:claude /home/claude /workspace

# Node.js + the ACP adapter, so JetBrains IDEs can talk to Claude over stdio.
# (Build time only: the firewall is not active while the image is built.)
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
# Maintained package (the old @zed-industries/claude-agent-acp is deprecated).
# 0.66.0 is a release other projects have tested; override with ACP_VERSION in .env.
ARG ACP_VERSION=0.66.0
RUN npm install -g "@agentclientprotocol/claude-agent-acp@${ACP_VERSION}"

USER claude
# "stable", "latest", or a pinned version such as 2.1.89 (set in .env).
# A pinned number is reproducible; changing it forces a fresh install layer.
ARG CLAUDE_VERSION=stable
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_VERSION}"
ENV PATH="/home/claude/.local/bin:${PATH}"

WORKDIR /workspace
