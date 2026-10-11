# Agent container: Claude Code as a non-root user, no extra capabilities.
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Ad-hoc search/inspection tools. fd/bat are installed under different names on
# Debian/Ubuntu (name clashes with other packages), so symlink them to the
# names everyone actually types.
RUN apt-get update && apt-get install -y --no-install-recommends \
    jq fd-find fzf silversearcher-ag bat \
    && ln -s "$(command -v fdfind)" /usr/local/bin/fd \
    && ln -s "$(command -v batcat)" /usr/local/bin/bat \
    && rm -rf /var/lib/apt/lists/*

# Native dev libraries Bevy's Linux backend links against at build time:
# Wayland/X11 windowing, ALSA audio, udev for input device hotplug.
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libwayland-dev libxkbcommon-dev libx11-dev libasound2-dev libudev-dev \
    && rm -rf /var/lib/apt/lists/*

# clang + lld: some mounted projects' .cargo/config.toml point the linker at
# these (faster links than system ld) via `linker = "clang"` / `-fuse-ld=lld`.
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang lld \
    && rm -rf /var/lib/apt/lists/*

# No real GPU or display in this container. xvfb is a virtual (invisible)
# X framebuffer so winit can open a window; mesa-vulkan-drivers provides
# lavapipe, a software Vulkan device, so wgpu has a backend to render with.
# Together they let a Bevy app run headless and save a screenshot to disk.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb mesa-vulkan-drivers \
    && rm -rf /var/lib/apt/lists/*

# winit's X11 backend dlopens these at runtime (not link time, so the -dev
# headers above don't cover them): libX11, libX11-xcb, libXcursor, libXi,
# and the X11 keymap extension for libxkbcommon (a separate package from the
# core libxkbcommon0 that libxkbcommon-dev already pulled in).
RUN apt-get update && apt-get install -y --no-install-recommends \
    libx11-6 libx11-xcb1 libxcursor1 libxi6 libxkbcommon-x11-0 \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships a default "ubuntu" user at UID 1000; replace it so the
# container user can match your host UID (avoids permission problems on the
# mounted project). Build with: HOST_UID=$(id -u) docker compose build
ARG HOST_UID=1000
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -u "${HOST_UID}" -s /bin/bash claude \
    && mkdir -p /home/claude/.claude /workspace \
    && chown -R claude:claude /home/claude /workspace

# Node.js + the ACP adapter, so JetBrains IDEs can talk to Claude over stdio.
# (Build time only: the firewall is not active while the image is built.)
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
# Maintained package (the old @zed-industries/claude-agent-acp is deprecated).
# 0.66.0 is a release other projects have tested; override with ACP_VERSION in .env.
ARG ACP_VERSION=0.66.0
RUN npm install -g "@agentclientprotocol/claude-agent-acp@${ACP_VERSION}"

USER claude
# "stable", "latest", or a pinned version such as 2.1.89 (set in .env).
# A pinned number is reproducible; changing it forces a fresh install layer.
ARG CLAUDE_VERSION=stable
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_VERSION}"
ENV PATH="/home/claude/.local/bin:${PATH}"

# Rust toolchain for inspecting Rust codebases: rustfmt/clippy for linting,
# rust-src so rust-analyzer can resolve std library sources.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
      --component rustfmt --component clippy --component rust-src --component rust-analyzer
ENV PATH="/home/claude/.cargo/bin:${PATH}"
# eza isn't in Ubuntu 24.04's repos yet; the toolchain above can build it directly.
# --locked: build against eza's checked-in Cargo.lock, not newer dep versions
# that fail to compile against this Rust version.
RUN cargo install eza --locked

# Projects can pin their own channel via rust-toolchain.toml, which rustup
# fetches on demand from static.rust-lang.org (not in the runtime firewall's
# allowlist, by design). Pre-installing the pin here at build time - when the
# firewall isn't active yet - means rustup finds it already present at
# runtime and never needs network. Update RUST_NIGHTLY_VERSION/components to
# match the mounted project's rust-toolchain.toml; override with --build-arg
# if a project needs a different pin.
ARG RUST_NIGHTLY_VERSION=2026-07-15
RUN rustup toolchain install "nightly-${RUST_NIGHTLY_VERSION}" \
      --component rustc-codegen-cranelift-preview

WORKDIR /workspace
