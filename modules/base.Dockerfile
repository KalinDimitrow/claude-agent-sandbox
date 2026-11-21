# Base for every other image: essential build tools and the agent user.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    clang \
    curl \
    git \
    lld \
    pkg-config \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships a default "ubuntu" user at UID 1000; replace it so the
# container user matches the host UID on the mounted project.
ARG HOST_UID=1000
ARG AGENT_USER=agent
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -u "${HOST_UID}" -s /bin/bash "${AGENT_USER}" \
    && mkdir -p /workspace \
    && chown "${AGENT_USER}:${AGENT_USER}" /workspace

USER ${AGENT_USER}
WORKDIR /workspace
