#!/bin/bash
# Stop and remove the sandbox containers (agent, firewall-init, netns-holder).
# The next bin/claude-box.sh starts them again with a fresh network namespace
# and re-runs the firewall.
#
#   stop.sh    stop the sandbox
#
# Named volumes (Claude login and settings in claude-config) are KEPT.
# This script deliberately never passes -v, which would delete them.
set -euo pipefail
# Scripts live in bin/; work from the sandbox root (compose file, .env).
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

PROJECT="$(grep -E '^COMPOSE_PROJECT_NAME=' .env 2>/dev/null | tail -1 | cut -d= -f2- || true)"
[ -n "$PROJECT" ] || { echo "Set COMPOSE_PROJECT_NAME in .env" >&2; exit 1; }

podman-compose -p "$PROJECT" down

# Report anything that survived (e.g. a container started outside compose).
left=$(podman ps -a --format '{{.Names}}' | grep -E "^${PROJECT}_" || true)
if [ -n "$left" ]; then
  echo "Still present:" >&2
  echo "$left" >&2
  exit 1
fi
echo "Sandbox stopped."
