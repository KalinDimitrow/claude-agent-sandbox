# The agent image, built by docker-compose.yml on top of the claude module
# (modules/agents/claude.Dockerfile), the last module in rebuild.sh's MODULES.
ARG PARENT=localhost/sandbox-claude
FROM ${PARENT}

ARG AGENT_USER=agent
USER ${AGENT_USER}
WORKDIR /workspace
