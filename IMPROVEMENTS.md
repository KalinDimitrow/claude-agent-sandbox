# Sandbox review — findings (2026-11-21)

Status: open. Nothing below has been fixed yet. Each issue lists one or more
suggested solutions (A, B, C...) to review and choose from. Notes marked
"Update" describe what changed since the original review.

## Critical

- [x] **Won't fix (2026-11-22).** This is a worktree the agent edits, not the
  copy the host runs. Agent changes reach the live sandbox only through a
  reviewed commit/merge. Original finding kept below for reference.

- [ ] **Agent can edit its own firewall.** `PROJECT_DIR=/home/kalin/Projects/ClaudeRepos`
  contains `agent-sandbox/`, so `init-firewall.sh` and `docker-compose.yml` are
  writable from inside the container (verified). `init-firewall.sh` is
  bind-mounted, so edits apply on the next `up` with no rebuild.
  Update: the same applies to `modules/*.Dockerfile` and `rebuild.sh`, so the
  agent could also plant something in the next image build.

  **Suggested solutions:**
  - **A. Move the sandbox out of the project dir** (recommended). E.g.
    `~/Projects/agent-sandbox`. Simplest, and fixes the problem completely.
  - **B. Narrow `PROJECT_DIR`** to a single project (e.g. `.../ClaudeRepos/game`).
    Works, but you switch projects by editing `.env`.
  - **C. Mount the sandbox dir read-only on top**: add a second volume
    `${PROJECT_DIR}/agent-sandbox:${PROJECT_DIR}/agent-sandbox:ro`. Keeps the
    current layout, but is easy to forget when paths change.
  - **In every case, add a guard** to `claude-box.sh` and `rebuild.sh`:
    ```bash
    here=$(pwd -P); proj=$(readlink -f "$pd")
    case "$here/" in "$proj"/*) echo "Refusing: sandbox is inside PROJECT_DIR" >&2; exit 1;; esac
    ```

## Security

- [ ] **All of GitHub's web/api/git ranges are allowed**, so data can be pushed
  or posted anywhere on GitHub. The agent has no credentials of its own, but a
  token planted in content it reads (prompt injection) would be enough.

  **Suggested solutions:**
  - **A. Remove GitHub from the allowlist.** Do all clone/pull/push on the
    host (see the git items below). Simplest and strongest.
  - **B. Hostname-filtering proxy** (see the next item): allow `github.com` and
    `codeload.github.com` for cloning, but block `api.github.com`,
    `gist.github.com` and `uploads.github.com`.
  - **C. Keep as is, but never put GitHub tokens in the container** and accept
    the injected-token risk.

- [ ] **The allowlist is IP-based and resolved once at startup.** Shared CDN IPs
  (npm, crates) allow other sites too, and rotating IPs break long sessions.

  **Suggested solutions:**
  - **A. Internal network plus proxy container** (recommended, larger change).
    - The agent goes on a podman network with `internal: true`, so it has no
      route out at all.
    - A proxy container (squid or tinyproxy) is on both the internal and the
      outside network.
    - The proxy allows only listed hostnames. For HTTPS it reads the name from
      the TLS handshake (squid `ssl_bump peek` + `splice`), so it doesn't
      decrypt traffic.
    - Set `HTTPS_PROXY`/`HTTP_PROXY` in the agent container.
    - This replaces `init-firewall.sh` entirely. No NET_ADMIN, no ipset, no
      startup timing.
  - **B. Proxy in the same network namespace plus iptables.** Keep the current
    firewall, but only allow outbound traffic from the proxy's uid
    (`-m owner --uid-owner <proxy uid>`). The agent may only connect to
    `127.0.0.1:3128`. Smaller change than A, but uid mapping with rootless
    podman needs testing.
  - **C. Keep IPs, but re-resolve every N minutes** in a small loop in the
    firewall container. Fixes rotating IPs only, not the shared-CDN problem.

- [ ] **DNS to the resolver is forwarded upstream**, so data can leak through
  DNS queries.

  **Suggested solutions:**
  - **A. With the proxy design (A above), give the agent no DNS at all.** The
    proxy resolves names. This removes the leak completely.
  - **B. Local dnsmasq as the only resolver.** Answer only allowlisted domains
    (`server=/npmjs.org/1.1.1.1` and so on), return nothing for everything else
    (`address=/#/`), and let only dnsmasq reach the upstream resolver.

- [ ] **IPv6 policy failures in `init-firewall.sh` are only warnings.**

  **Suggested solutions:**
  - **A. Make them fatal.** In lines 145–156, replace each
    `|| echo "WARNING…"` / `|| true` with `|| { echo "ERROR…"; exit 1; }`, and
    exit with an error when `ip6tables` is missing.
  - **B. Also disable IPv6 in the network namespace**, as a second layer: add
    `sysctls: [net.ipv6.conf.all.disable_ipv6=1]` to `netns-holder`.
  - Do both: A and B together are only a few lines.

- [ ] **Downloads are not checksummed** (Blender, nodesource, claude, rustup).
  Bun is gone.

  **Suggested solutions:**
  - **Blender:** add `ARG BLENDER_SHA256` and check the file with
    `echo "$BLENDER_SHA256  file.tar.xz" | sha256sum -c`. Blender publishes
    `.sha256` files next to each release.
  - **Rustup:** download the `rustup-init` binary and its `.sha256` instead of
    the shell script and check it. Same origin, so this mostly protects against
    a corrupt download. Pin the hash for real protection.
  - **Nodesource:**
    - Option A: skip the setup script. Add their apt repo directly, with the
      key's fingerprint pinned.
    - Option B: install Node from the official `nodejs.org` tarball and check
      it against the published `SHASUMS256.txt`.
  - **Claude:**
    - Option A: pin an exact `CLAUDE_VERSION` instead of `stable`.
    - Option B: install via `npm install -g @anthropic-ai/claude-code@<version>`.
      npm checks package integrity.

- [ ] **`.env` is not in `.gitignore`, and `.env.example`** (referenced in the
  comments) does not exist.

  **Suggested solution:** add `.env` to `.gitignore`. Create `.env.example`
  with `COMPOSE_PROJECT_NAME`, `PROJECT_DIR`, `HOST_UID`, `AGENT_USER`,
  `CLAUDE_VERSION`, `ACP_VERSION` and `WAYLAND_DISPLAY`, plus
  `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` commented out.

- [ ] **Git config and hooks can run code on the host.**
  Update: this is wider than hooks. `.git/config` settings like
  `core.fsmonitor`, `core.pager`, aliases and filters also run commands.
  For `game/` and `agent-sandbox/` (both worktrees), hooks and config live in
  the main repo's `.git`, which isn't mounted, so they can't be edited today.
  But the `.git` *pointer file* is writable: the agent can replace it with a
  directory holding its own `config`/`hooks`. The next git command on the
  host, including the IDE's background git, runs that code.

  **Suggested solutions:**
  - **A. Separate clones plus fetch from the host** (recommended).
    - The agent works in its own clones inside `PROJECT_DIR`.
    - On the host, keep your own clone and `git fetch` from the agent's copy
      (`git remote add agent /path/to/agent/clone`).
    - Fetch never runs the source repo's config or hooks.
    - Never run git, or open an IDE with git integration, directly in the
      agent's folders on the host.
    - Fixes the "git is broken" item below too.
  - **B. Run git only inside the container**, and don't let the host IDE touch
    the agent's folders. Simple, but easy to break by accident (IDE).
  - **C. Harden host git**, as a partial measure: in host `~/.gitconfig`, set
    `core.hooksPath` to an empty directory and `core.fsmonitor = false`. This
    doesn't cover every config-based command, and breaks hook-based tools
    (husky, pre-commit) in all repos.

## Functional

- [ ] **Git is broken in the container**: the worktree gitdirs
  (`/home/kalin/Projects/game/.git`, `/home/kalin/Projects/claude-agent/.git`)
  are not mounted.
  Update: this breakage is currently what keeps hooks/config out of the
  agent's reach (see above). Mounting the gitdirs brings that risk back in
  full.

  **Suggested solutions:**
  - **A. Separate clones** (same as A above, recommended). Git works fully in
    the container, and the host only fetches.
  - **B. Mount the gitdirs at the same paths** (read-write). Git works, but the
    agent can then edit hooks/config of your main repos. Not recommended.
  - **C. Mount the gitdirs read-only.** `git status`/`log`/`diff` work, but
    commit doesn't. The agent can still swap the `.git` pointer file, so the
    host risk stays.

- [ ] **No persistent cargo caches**: `~/.cargo-target-cache` (used by game's
  CLAUDE.md) and `~/.cargo/registry` are not volumes, so every `down` means a
  full Bevy rebuild plus re-downloading crates.

  **Suggested solution:** add named volumes:
  ```yaml
  - cargo-registry:/home/agent/.cargo/registry
  - cargo-git:/home/agent/.cargo/git
  - cargo-target:/home/agent/.cargo-target-cache
  ```
  Create those directories in `rust.Dockerfile`, owned by the agent user, so
  new volumes get the right ownership. Also update game's `CLAUDE.md` and
  `.claude/settings.local.json`, which still use `/home/claude` paths.
  Alternative: use `sccache` with one cache volume instead of a shared target
  dir.

- [ ] **No memory/CPU limits** (only `pids_limit`).

  **Suggested solution:** the host has 16 cores and 62 GB RAM. Something like:
  ```yaml
  mem_limit: 24g
  memswap_limit: 24g
  cpus: 12
  ```
  If Bevy builds run out of memory, also set `CARGO_BUILD_JOBS` (e.g. 8).

- [ ] **Dockerfile layer order / Claude version refresh.**
  Update: mostly fixed. `agents/claude` is now the last module, so bumping
  `CLAUDE_VERSION` no longer rebuilds rust/blender. Still open: `stable` never
  refreshes, because `rebuild.sh --force` still uses podman's build cache.

  **Suggested solutions:**
  - **A. Resolve `stable` to a concrete version** in `rebuild.sh` and pass that
    as `CLAUDE_VERSION`. The cache invalidates exactly when a new version comes
    out.
  - **B. Cache-bust arg**: `ARG CLAUDE_CACHE_BUST` in `claude.Dockerfile`, and
    `rebuild.sh --force` passes `--build-arg CLAUDE_CACHE_BUST=$(date +%s)`.
  - **C. `--force` means `--no-cache`** for all modules. Simple but slow: it
    rebuilds everything.

- [ ] **Startup relies on timing**: the `sleep 3` in `claude-box.sh` and the
  "may start twice" check in `init-firewall.sh`.

  **Suggested solutions:**
  - **A. Run the firewall step outside compose.**
    1. `podman-compose up -d netns-holder`
    2. `podman run --rm --network container:<holder> --cap-add NET_ADMIN,NET_RAW … firewall`,
       then check its exit code directly.
    3. `podman-compose up -d --no-deps claude`

    This removes the polling loop, the `sleep 3` and the "already active"
    branch.
  - **B. Smallest change:** replace the polling loop with
    `code=$(podman wait "$FW")`, which blocks until the container exits and
    returns its exit code. The "may start twice" problem remains.
  - **C. Becomes moot** with the internal network plus proxy design (see
    Security), since there is no firewall init step.

## Cleanup

- [x] **`init-firewall.sh` lines 159–173 duplicate `verify()`.** Done 2026-11-22.
  **Suggested solution:** replace them with a call to `verify`.

- [ ] **Docker vs podman.** The compose and `.env` comments give Docker
  commands, but the scripts are podman-only, and `userns_mode: keep-id` /
  `group_add: keep-groups` don't work with Docker.
  **Suggested solutions:**
  - **A. Podman only** (recommended). Rewrite the header of
    `docker-compose.yml` to use `bin/rebuild.sh`, `bin/claude-box.sh` and `bin/stop.sh`, and
    consider renaming it to `compose.yml`.
  - **B. Support both**: a `docker-compose.podman.yml` overlay holding the
    podman-only options. More to maintain.

- [ ] **Project-specific tooling baked into the sandbox.**
  Update: mostly done through the `MODULES` list in `rebuild.sh`, and Bun has
  been dropped. Remaining: the module list is global, not per project.
  **Suggested solutions:**
  - **A. `MODULES=` line in `.env`** (space-separated), read by `rebuild.sh`.
  - **B. Profile files**, e.g. `profiles/game.list` with one module per line,
    chosen with `PROFILE=game` in `.env`. Gives each profile its own image tag,
    so switching projects doesn't rebuild.

- [ ] **Merge the `apt-get update` layers; install eza from a release
  binary.**
  Update: merging the apt layers conflicts with the rule that each module is
  self-sufficient.
  **Suggested solutions:**
  - **apt layers:** drop this item. Each module already removes its apt lists,
    so the cost is small.
  - **eza:**
    - Option A: download the release tarball from GitHub releases with a
      pinned sha256, in `tools.Dockerfile`, so the rust module no longer
      needs it.
    - Option B: `cargo binstall eza`. Fetches a prebuilt binary, but needs
      cargo-binstall first.
    - Option C: drop eza and use `ls`.

- [ ] **`RUST_NIGHTLY_VERSION` can drift from the project's
  `rust-toolchain.toml`.**
  **Suggested solutions:**
  - **A. `rebuild.sh` reads it from the project:**
    `grep -Po 'channel\s*=\s*"\K[^"]+' "$PROJECT_DIR/game/rust-toolchain.toml"`,
    and passes it as a build arg.
  - **B. Don't bake the nightly into the image at all.** rustup installs it on
    first use from `rust-toolchain.toml`. Needs `~/.rustup` as a named volume,
    and the rustup domains in the allowlist.

## Suggested order

1. ~~Critical: move the sandbox out of `PROJECT_DIR` and add the guard.~~
   Won't fix, see above.
2. Quick wins: make IPv6 failures fatal, remove the duplicate `verify()`,
   fix `.env`/`.gitignore`, fix the podman comments.
3. Cargo volumes and resource limits.
4. Separate clones plus fetch from the host (fixes git and hooks together).
5. Internal network plus proxy (replaces the GitHub, IP-allowlist, DNS and
   startup-timing items).
