ARG BUILD_FROM
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

# hadolint ignore=DL3006
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV \
    HOME="/root" \
    LANG="C.UTF-8" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_FIND_LINKS=https://wheels.home-assistant.io/musllinux/ \
    PIP_NO_CACHE_DIR=1 \
    PIP_PREFER_BINARY=1 \
    PS1="$(whoami)@$(hostname):$(pwd)$ " \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_CMD_WAIT_FOR_SERVICES=1 \
    TERM="xterm-256color"

ENV S6_KILL_GRACETIME=30000
ENV S6_SYNC_DISKS=1

ARG BUILD_ARCH

RUN apk add --no-cache \
    samba-common-tools \
    samba-server \
    samba-client \
    exfatprogs \
    btrfs-progs \
    xfsprogs \
    udev \
    eudev \
    hwids-udev \
    device-mapper-udev \
    attr \
    e2fsprogs \
    util-linux \
    e2fsprogs-extra \
    curl \
    findmnt \
    ntfs-3g-progs \
    hdparm \
    hd-idle \
    fuse3 \
    py3-pip \
    pipx \
    poetry \
    lsblk \
    jq \
    figlet

RUN if [ "$BUILD_ARCH" != "armv7" ]; then apk add --no-cache apfs-fuse; fi

# Enable APFS mount support
RUN if [ "$BUILD_ARCH" != "armv7" ]; then ln -s /usr/sbin/apfs-fuse /usr/sbin/mount.apfs; fi

# Create Samba required directories and files
RUN mkdir -p /var/lib/samba \
    && touch \
    /etc/samba/lmhosts \
    /var/lib/samba/account_policy.tdb \
    /var/lib/samba/registry.tdb \
    /var/lib/samba/winbindd_idmap.tdb \
    /etc/samba/smb.conf

# Create internal Samba service account (password set at runtime)
RUN adduser -D -H -s /sbin/nologin _mountit_

# Copy addon files
COPY rootfs /

# Ensure all service scripts are executable (Windows git does not preserve +x bits)
RUN find /etc/s6-overlay/s6-rc.d -name run -o -name finish -o -name up -o -name down \
    | xargs chmod a+x 2>/dev/null || true

# Install Python dependencies (diskinfo library)
RUN cd /usr/local/bin/ && poetry install --no-interaction

HEALTHCHECK CMD smbclient -L '\\localhost' -U '%' -m SMB3

LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="Mount It" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${BUILD_VERSION}
