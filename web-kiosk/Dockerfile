# https://developers.home-assistant.io/docs/apps/configuration#app-dockerfile
FROM ghcr.io/home-assistant/base:3.24-2026.08.0 AS base

# ------------------------------------------------------------------------------
# Cage, patched so touch input follows a rotated output (see patches/).
# ------------------------------------------------------------------------------
FROM base AS cage-build

ARG CAGE_VERSION=0.3.1
ARG CAGE_SHA256=edafc173b6f56a3e1564933e272a54aaa9fe158d330e6a415d57b44ab880fe2b

RUN apk add --no-cache \
        build-base \
        libxkbcommon-dev \
        meson \
        wayland-dev \
        wayland-protocols \
        wlroots0.20-dev

ADD --checksum=sha256:${CAGE_SHA256} \
    "https://github.com/cage-kiosk/cage/releases/download/v${CAGE_VERSION}/cage-${CAGE_VERSION}.tar.gz" \
    /tmp/cage.tar.gz
COPY patches/ /tmp/patches/
WORKDIR /tmp/cage-${CAGE_VERSION}

RUN tar -xzf /tmp/cage.tar.gz -C /tmp \
    && for patch in /tmp/patches/*.patch; do patch -p1 < "${patch}"; done \
    && meson setup build --buildtype=release -Dman-pages=disabled \
    && meson compile -C build \
    && install -Dm755 build/cage /out/usr/bin/cage

# ------------------------------------------------------------------------------
# App image
# ------------------------------------------------------------------------------
FROM base

RUN apk add --no-cache \
        chromium \
        font-noto \
        font-noto-cjk \
        font-noto-emoji \
        libinput-tools \
        mesa-dri-gallium \
        mesa-egl \
        mesa-gbm \
        wlr-randr \
        wlroots0.20

COPY --from=cage-build /out/ /
COPY rootfs /

# Supplied by the Supervisor and by the Home Assistant build actions.
ARG BUILD_VERSION=dev

# Give Chromium time to flush the profile (cookies, localStorage) on shutdown.
ENV \
    KIOSK_VERSION=${BUILD_VERSION} \
    S6_SERVICES_GRACETIME=6000

LABEL \
    org.opencontainers.image.title="Home Assistant App: Web Kiosk" \
    org.opencontainers.image.description="Shows a configured URL full-screen on the locally attached display." \
    org.opencontainers.image.source="https://github.com/korellas/haos-web-kiosk" \
    org.opencontainers.image.licenses="MIT"
