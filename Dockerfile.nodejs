# Node.js (with npm) from NodeSource; Ubuntu's own package is too old.
ARG PARENT=localhost/sandbox-base
FROM ${PARENT}

USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

ARG NODE_MAJOR=24
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource-setup.sh \
    && bash /tmp/nodesource-setup.sh \
    && rm /tmp/nodesource-setup.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

ARG AGENT_USER=agent
USER ${AGENT_USER}
