#!/bin/bash
# Bring the sandbox down, rebuild images only if the files that define them
# changed since the last rebuild, then bring it back up. Run this after
# editing a Dockerfile*/docker-compose.yml/.env or the module list below,
# before claude-box.sh.
#
#   rebuild.sh            rebuild only if tracked files changed
#   rebuild.sh --force    rebuild unconditionally (e.g. after an upstream base-image update)
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Image modules, built in this order, each on top of the previous one
# (Dockerfile.<name> -> localhost/sandbox-<name>). Comment a line to drop a
# module; base must stay first. The final Dockerfile builds on the last one.
MODULES=(
  base
  tools
  rust
  desktop
  blender
  nodejs
  claude
)

# Files baked into the images at build time. init-firewall.sh is deliberately
# excluded: it's bind-mounted read-only at runtime (see docker-compose.yml),
# so edits to it take effect on the next `up` without needing a rebuild.
TRACKED_FILES=(Dockerfile Dockerfile.* docker-compose.yml .env rebuild.sh)
STATE_FILE=".last-build-state"

state() {
  # git hash-object reads each file's current on-disk content, so uncommitted
  # edits count too, not just committed ones.
  for f in "${TRACKED_FILES[@]}"; do
    git hash-object "$f"
  done | sha256sum | cut -d' ' -f1
}

env_value() {
  [ -f .env ] && grep -E "^$1=" .env | tail -1 | cut -d= -f2- || true
}

build_modules() {
  [ "${MODULES[0]}" = "base" ] || { echo "MODULES must start with base" >&2; exit 1; }

  local args=() key value parent="" m
  for key in HOST_UID AGENT_USER CLAUDE_VERSION ACP_VERSION; do
    value="$(env_value "$key")"
    [ -n "$value" ] && args+=(--build-arg "$key=$value")
  done

  for m in "${MODULES[@]}"; do
    echo "--- building module: $m"
    podman build -f "Dockerfile.$m" -t "localhost/sandbox-$m" \
      ${parent:+--build-arg "PARENT=$parent"} ${args[@]+"${args[@]}"} .
    parent="localhost/sandbox-$m"
  done
  podman tag "$parent" localhost/sandbox-modules
}

current="$(state)"
previous=""
[ -f "$STATE_FILE" ] && previous="$(cat "$STATE_FILE")"

podman-compose down

if [ "${1:-}" = "--force" ] || [ "$current" != "$previous" ]; then
  echo "Tracked Dockerfile/compose files changed (or --force) - rebuilding images..."
  build_modules
  podman-compose build
  echo "$current" > "$STATE_FILE"
else
  echo "No changes to ${TRACKED_FILES[*]} since last build; skipping rebuild."
fi

podman-compose up -d

echo "Up. Run ./claude-box.sh to start Claude Code."
