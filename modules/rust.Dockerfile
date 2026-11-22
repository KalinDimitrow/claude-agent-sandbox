# Rust via rustup: stable toolchain with lint/format/IDE components, eza, and
# a pinned nightly for projects that require one.
ARG PARENT=localhost/sandbox-base
FROM ${PARENT}

USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    pkg-config \
# some projects' .cargo/config.toml set `linker = "clang"` / `-fuse-ld=lld`
    clang \
    lld \
    && rm -rf /var/lib/apt/lists/*

ARG AGENT_USER=agent
USER ${AGENT_USER}

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y \
      --component rustfmt --component clippy --component rust-src --component rust-analyzer \
    && rm /tmp/rustup-init.sh
ENV PATH="/home/${AGENT_USER}/.cargo/bin:${PATH}"

# Not in Ubuntu 24.04's repos. --locked: newer dependency versions may not
# compile with this toolchain.
RUN cargo install eza --locked

# rustup fetches a rust-toolchain.toml pin from static.rust-lang.org, which the
# runtime firewall blocks; installing it at build time avoids that. Match the
# mounted project's rust-toolchain.toml.
ARG RUST_NIGHTLY_VERSION=2026-07-15
RUN rustup toolchain install "nightly-${RUST_NIGHTLY_VERSION}" \
      --component rustc-codegen-cranelift-preview
