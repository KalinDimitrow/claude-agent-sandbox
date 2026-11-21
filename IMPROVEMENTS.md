# Sandbox review — findings (2026-11-21)

Status: open. Nothing below has been fixed yet.

## Critical

- [ ] **Agent can edit its own firewall.** `PROJECT_DIR=/home/kalin/Projects/ClaudeRepos`
  contains `agent-sandbox/`, so `init-firewall.sh` and `docker-compose.yml` are
  writable from inside the container (verified). `init-firewall.sh` is
  bind-mounted, so edits apply on the next `up` with no rebuild. Fix: move
  `agent-sandbox` outside `PROJECT_DIR` (or narrow `PROJECT_DIR`), and make
  `claude-box.sh` refuse to start if the sandbox dir is inside `PROJECT_DIR`.

## Security

- [ ] All of GitHub's web/api/git ranges are allowed, so data can be pushed or
  posted anywhere on GitHub. Consider a domain/path-filtering proxy, and don't
  give the agent GitHub credentials.
- [ ] The allowlist is IP-based and resolved once at startup. Shared CDN IPs
  (npm, crates) allow other sites too, and rotating IPs break long sessions.
  Fix: an HTTPS proxy sidecar (squid/tinyproxy) that filters on hostname/SNI,
  with the firewall allowing only the proxy.
- [ ] DNS to the resolver is forwarded upstream, so data can leak through DNS
  queries. Fix: a local resolver that only answers for allowlisted domains.
- [ ] IPv6 policy failures in `init-firewall.sh` are only warnings. Make them
  fatal so the lockdown path runs.
- [ ] Downloads are piped from curl without checksums (Blender, nodesource,
  claude, rustup, bun). At least pin a sha256 for Blender.
- [ ] `.env` is not in `.gitignore`, and `.env.example`, which the comments
  refer to, does not exist.
- [ ] The agent can write `.git/hooks`, which then run on the host. Use
  `core.hooksPath` on the host, or run git only inside the container.

## Functional

- [ ] Git is broken in the container: the worktree gitdirs
  (`/home/kalin/Projects/game/.git`, `/home/kalin/Projects/claude-agent/.git`)
  are not mounted. Mount them at the same paths, or use normal clones.
- [ ] No persistent cargo caches: `/home/claude/.cargo-target-cache` (used by
  game's CLAUDE.md) and `~/.cargo/registry` are not volumes, so every `down`
  means a full Bevy rebuild plus re-downloading crates. Add named volumes.
- [ ] No memory/CPU limits (only `pids_limit`). Add `mem_limit` and `cpus`.
- [ ] Dockerfile layer order: Claude is installed before rustup, eza, nightly
  and bun. Bumping `CLAUDE_VERSION` rebuilds all of those, and `stable` never
  refreshes from cache. Move the Claude install last and add a cache-bust arg.
- [ ] Startup relies on timing: the `sleep 3` in `claude-box.sh` and the
  "may start twice" check in `init-firewall.sh`. Use `podman wait` or plain
  `podman run` sequencing instead.

## Cleanup

- [ ] `init-firewall.sh` lines 159–178 duplicate `verify()`; call `verify` instead.
- [ ] Docker vs podman: the compose and `.env` comments give Docker commands,
  but the scripts are podman-only, and `userns_mode: keep-id` doesn't work with
  Docker. Pick one and document only that.
- [ ] Project-specific tooling (Blender, Bevy libs, nightly pin) is
  baked into the sandbox. Bun is being dropped: it was only for gstack, which
  is no longer used. Split into a base image plus a per-project layer.
- [ ] Merge the five `apt-get update` layers into one, and install eza from a
  release binary instead of compiling it.
- [ ] Have `rebuild.sh` read `RUST_NIGHTLY_VERSION` from the project's
  `rust-toolchain.toml` so the two can't drift apart.
