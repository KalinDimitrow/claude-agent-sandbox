#!/bin/bash
# Start the sandbox if needed, REFUSE to continue unless the firewall succeeded,
# then run Claude inside the container.
#
#   claude-box.sh          interactive Claude Code in your terminal
#   claude-box.sh --acp    ACP adapter on stdin/stdout, for JetBrains IDEs
#                          (register it in ~/.jetbrains/acp.json)
#   claude-box.sh --acp-test   hand-made ACP handshake, to debug connection errors
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

PROJECT="${COMPOSE_PROJECT:-$(basename "$PWD")}"
FW="${PROJECT}_firewall-init_1"
AGENT="${PROJECT}_claude_1"

ensure_up() {
  local running st code
  running=$(podman inspect -f '{{.State.Running}}' "$AGENT" 2>/dev/null || echo false)
  if [ "$running" != "true" ]; then
    podman-compose down >/dev/null 2>&1 || true   # fresh network namespace
    podman-compose up -d
    for _ in $(seq 1 60); do   # wait up to 60s for firewall-init to finish
      st=$(podman inspect -f '{{.State.Status}}' "$FW" 2>/dev/null || echo missing)
      [ "$st" = "exited" ] && break
      sleep 1
    done
    sleep 3   # guard against firewall-init being started a second time
  fi

  st=$(podman inspect -f '{{.State.Status}}' "$FW" 2>/dev/null || echo missing)
  if [ "$st" != "exited" ]; then
    echo "firewall-init is still running (status: $st); try again in a few seconds." >&2
    exit 1
  fi
  code=$(podman inspect -f '{{.State.ExitCode}}' "$FW" 2>/dev/null || echo missing)
  if [ "$code" != "0" ]; then
    echo "Firewall did not complete successfully (exit: $code). Stopping the agent." >&2
    podman stop "$AGENT" >/dev/null 2>&1 || true
    podman logs "$FW" 2>&1 | tail -15 >&2 || true
    exit 1
  fi
}

pd=""
# Fail early, with a readable message, if PROJECT_DIR in .env is unusable.
# (podman-compose does not expand "~", and then fails with a cryptic traceback.)
if [ -f .env ]; then
  pd=$(grep -E '^PROJECT_DIR=' .env | tail -1 | cut -d= -f2- || true)
  case "$pd" in
    /*) ;;
    *) echo "PROJECT_DIR in .env must be a full path starting with / (got: '${pd}'). Do not use ~." >&2
       exit 1 ;;
  esac
  [ -d "$pd" ] || { echo "PROJECT_DIR does not exist: $pd" >&2; exit 1; }
fi

# In --acp mode stdout carries the protocol, so ALL setup output goes to stderr,
# and setup must not read stdin (the IDE may already be sending messages).
ensure_up >&2 </dev/null

if [ "${1:-}" = "--acp-test" ]; then
  # Debug aid: do the ACP handshake by hand and show what the adapter says.
  [ -n "${pd:-}" ] || { echo "--acp-test needs PROJECT_DIR in .env" >&2; exit 1; }
  echo "Sending initialize + session/new (cwd=$pd) to the adapter; waiting ${ACP_TEST_WAIT:-25}s for replies..." >&2
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}'
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/new\",\"params\":{\"cwd\":\"$pd\",\"mcpServers\":[]}}"
    sleep "${ACP_TEST_WAIT:-25}"
  } | podman exec -i "$AGENT" claude-agent-acp
  exit 0
fi

if [ "${1:-}" = "--acp" ]; then
  shift
  # The IDE may add flags of its own. "--cli" means "run Claude Code's own CLI"
  # (used for the IDE's log-in step); the adapter itself does not accept it.
  cli=""; args=()
  for a in "$@"; do
    if [ "$a" = "--cli" ]; then cli=1; else args+=("$a"); fi
  done
  if [ -n "$cli" ]; then
    # Drop adapter-only flags that plain `claude` does not understand.
    cli_args=()
    for a in ${args[@]+"${args[@]}"}; do
      [ "$a" = "--hide-claude-auth" ] || cli_args+=("$a")
    done
    tty_flag=""; [ -t 0 ] && tty_flag="-t"
    # shellcheck disable=SC2086
    exec podman exec -i $tty_flag "$AGENT" claude ${cli_args[@]+"${cli_args[@]}"}
  fi
  # Normal ACP session. No -t: a TTY would corrupt the protocol stream.
  exec podman exec -i "$AGENT" claude-agent-acp ${args[@]+"${args[@]}"}
fi
exec podman exec -it "$AGENT" claude "$@"
