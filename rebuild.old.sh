#!/bin/bash
# Fallback for the pre-module setup (Dockerfile.old, docker-compose.old.yml).
# Bring the sandbox down, rebuild images only if the files that define them
# changed since the last rebuild, then bring it back up. Run this after
# editing Dockerfile.old/Dockerfile.firewall/docker-compose.old.yml/.env,
# before claude-box.old.sh.
#
#   rebuild.old.sh            rebuild only if tracked files changed
#   rebuild.old.sh --force    rebuild unconditionally (e.g. after an upstream base-image update)
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Files baked into the images at build time. init-firewall.sh is deliberately
# excluded: it's bind-mounted read-only at runtime (see docker-compose.old.yml),
# so edits to it take effect on the next `up` without needing a rebuild.
COMPOSE=(podman-compose -f docker-compose.old.yml)
TRACKED_FILES=(Dockerfile.old Dockerfile.firewall docker-compose.old.yml .env)
STATE_FILE=".last-build-state.old"

state() {
  # git hash-object reads each file's current on-disk content, so uncommitted
  # edits count too, not just committed ones.
  for f in "${TRACKED_FILES[@]}"; do
    git hash-object "$f"
  done | sha256sum | cut -d' ' -f1
}

current="$(state)"
previous=""
[ -f "$STATE_FILE" ] && previous="$(cat "$STATE_FILE")"

"${COMPOSE[@]}" down

if [ "${1:-}" = "--force" ] || [ "$current" != "$previous" ]; then
  echo "Tracked Dockerfile/compose files changed (or --force) - rebuilding images..."
  "${COMPOSE[@]}" build
  echo "$current" > "$STATE_FILE"
else
  echo "No changes to ${TRACKED_FILES[*]} since last build; skipping rebuild."
fi

"${COMPOSE[@]}" up -d

echo "Up. Run ./claude-box.old.sh to start Claude Code."
