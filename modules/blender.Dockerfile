# Blender from the official tarball. Not apt's package: Ubuntu 24.04 ships 4.0,
# which lacks the Action Slots API (4.4+), and Debian's build drops Blender's
# bundled Python, so its FBX importer can't find numpy.
ARG PARENT=localhost/sandbox-desktop
FROM ${PARENT}

USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
# download and unpack
    ca-certificates \
    curl \
    xz-utils \
# runtime libraries the Blender binary links against
    libegl1 \
    libgl1 \
    libsm6 \
    libx11-6 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxinerama1 \
    libxkbcommon0 \
    libxrender1 \
    libxxf86vm1 \
    && rm -rf /var/lib/apt/lists/*

ARG BLENDER_VERSION=5.2.2
RUN curl -fsSL "https://download.blender.org/release/Blender${BLENDER_VERSION%.*}/blender-${BLENDER_VERSION}-linux-x64.tar.xz" \
      | tar -xJ -C /opt \
    && ln -sf "/opt/blender-${BLENDER_VERSION}-linux-x64/blender" /usr/local/bin/blender

ARG AGENT_USER=agent
USER ${AGENT_USER}
