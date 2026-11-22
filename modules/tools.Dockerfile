# Command-line tools for searching, inspecting and editing code and data.
ARG PARENT=localhost/sandbox-base
FROM ${PARENT}

USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
# search and view
    bat \
    fd-find \
    fzf \
    less \
    ripgrep \
    silversearcher-ag \
    tree \
# files and archives
    file \
    patch \
    rsync \
    zip \
# text and data
    bsdextrautils \
    jq \
    moreutils \
    sqlite3 \
    xxd \
# processes
    htop \
    lsof \
    procps \
    psmisc \
# network debugging
    dnsutils \
    netcat-openbsd \
    wget \
# editing and terminal
    nano \
    tmux \
    vim-tiny \
# code quality
    hyperfine \
    shellcheck \
    && rm -rf /var/lib/apt/lists/*

# Debian/Ubuntu install fd and bat as fdfind/batcat (name clashes with other
# packages); expose them under their usual names when present.
RUN if command -v fdfind >/dev/null; then ln -sf "$(command -v fdfind)" /usr/local/bin/fd; fi \
    && if command -v batcat >/dev/null; then ln -sf "$(command -v batcat)" /usr/local/bin/bat; fi

ARG AGENT_USER=agent
USER ${AGENT_USER}
