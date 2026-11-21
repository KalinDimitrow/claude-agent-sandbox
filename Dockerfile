# The agent image: the last module of the chain built by rebuild.sh, which
# tags it localhost/sandbox-modules. Modules are listed in rebuild.sh.
ARG PARENT=localhost/sandbox-modules
FROM ${PARENT}

ARG AGENT_USER=agent
USER ${AGENT_USER}
WORKDIR /workspace
