# Desktop applications: windowing, input, graphics and audio. Works both
# headless (xvfb + lavapipe) and on the host's Wayland session with the GPU
# (sockets and /dev/dri are shared by docker-compose.yml).
ARG PARENT=localhost/sandbox-base
FROM ${PARENT}

USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
# build time: headers that windowing/input/audio crates link against
    libasound2-dev \
    libudev-dev \
    libwayland-dev \
    libx11-dev \
    libxkbcommon-dev \
    pkg-config \
# runtime: dlopened by winit, so the -dev packages are not enough on their own
    libwayland-client0 \
    libwayland-cursor0 \
    libwayland-egl1 \
    libx11-6 \
    libx11-xcb1 \
    libxcursor1 \
    libxi6 \
    libxkbcommon0 \
    libxkbcommon-x11-0 \
# graphics: mesa provides RADV (AMD) and lavapipe (software) for Vulkan, and
# the GL/EGL/GBM drivers that Electron/Chromium apps render with
    libegl1 \
    libgbm1 \
    libgl1-mesa-dri \
    mesa-vulkan-drivers \
    vulkan-tools \
# audio: routes ALSA output to the host's PulseAudio/PipeWire socket
    libasound2-plugins \
# fonts: without any, GUI text renders as empty boxes
    fonts-dejavu-core \
# headless display: virtual X server for running without the host session
    xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN printf 'pcm.!default { type pulse }\nctl.!default { type pulse }\n' > /etc/asound.conf

# Xvfb creates its socket here; pre-create it root-owned with /tmp semantics,
# as X expects.
RUN install -d -m 1777 /tmp/.X11-unix

ARG AGENT_USER=agent
USER ${AGENT_USER}
RUN install -d -m 700 "${HOME}/.xdg-runtime"
