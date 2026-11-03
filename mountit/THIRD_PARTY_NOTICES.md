# Third-party notices

Mount It is built on the open-source components below. This repository only contains Mount It's own scripts, configuration and images: when Home Assistant installs Mount It, it builds the app on your device from the [Dockerfile](Dockerfile). The build downloads the base image from GitHub's container registry, installs Alpine Linux packages from Alpine's package repository and Python packages from PyPI, so each component comes from its own source and is used under its own license.

## Base image

| Component | Version | License | Source |
| --- | --- | --- | --- |
| [Home Assistant Community Add-ons base image](https://github.com/hassio-addons/addon-base) | 17.2.5 | MIT | <https://github.com/hassio-addons/addon-base> |
| [Alpine Linux](https://alpinelinux.org/) (via the base image) | 3.21 | various, see [below](#supporting-alpine-packages) | <https://gitlab.alpinelinux.org/alpine/aports/-/tree/3.21-stable> |
| [s6-overlay](https://github.com/just-containers/s6-overlay) (includes skarnet.org's s6, s6-rc, execline and skalibs) | 3.2.0.2 | ISC | <https://github.com/just-containers/s6-overlay> |
| [bashio](https://github.com/hassio-addons/bashio) | 0.17.0 | MIT | <https://github.com/hassio-addons/bashio> |
| [tempio](https://github.com/home-assistant/tempio) | 2024.11.2 | Apache-2.0 | <https://github.com/home-assistant/tempio> |

## Main components

The Alpine packages Mount It installs (see the [Dockerfile](Dockerfile)). Licenses are as recorded in Alpine's package database.

| Component | Version | License | Source |
| --- | --- | --- | --- |
| [Samba](https://www.samba.org/) (`samba-server`, `samba-client`, `samba-common-tools`; serves the drives to Home Assistant) | 4.20.6-r1 | GPL-3.0-or-later AND LGPL-3.0-or-later | <https://www.samba.org/> |
| [exfatprogs](https://github.com/exfatprogs/exfatprogs) | 1.2.6-r0 | GPL-2.0-or-later | <https://github.com/exfatprogs/exfatprogs> |
| [btrfs-progs](https://btrfs.readthedocs.io/) | 6.11-r2 | GPL-2.0-or-later | <https://btrfs.wiki.kernel.org> |
| [xfsprogs](https://xfs.wiki.kernel.org/) | 6.10.1-r0 | LGPL-2.1-or-later | <https://xfs.org/index.php/Main_Page> |
| [eudev](https://github.com/eudev-project/eudev) (`eudev`, `eudev-hwids`; installed through `udev` and `hwids-udev`) | 3.2.14-r5 | GPL-2.0-or-later | <https://github.com/eudev-project/eudev> |
| [LVM2 device-mapper](https://sourceware.org/lvm2/) (`device-mapper-udev`) | 2.03.29-r1 | GPL-2.0-or-later AND LGPL-2.1-or-later AND BSD-2-Clause | <https://sourceware.org/lvm2/> |
| [attr](https://savannah.nongnu.org/projects/attr) | 2.5.2-r2 | LGPL-2.1-or-later | <https://savannah.nongnu.org/projects/attr> |
| [e2fsprogs](https://e2fsprogs.sourceforge.net/) (`e2fsprogs`, `e2fsprogs-extra`) | 1.47.1-r1 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT | <https://e2fsprogs.sourceforge.net/> |
| [util-linux](https://github.com/util-linux/util-linux) (`util-linux`, `findmnt`, `lsblk`) | 2.40.4-r1 | GPL-3.0-or-later AND GPL-2.0-or-later AND GPL-2.0-only AND GPL-1.0-only AND LGPL-2.1-or-later AND BSD-1-Clause AND BSD-3-Clause AND BSD-4-Clause-UC AND MIT AND Public-Domain; GPL-2.0-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| [NTFS-3G](https://github.com/tuxera/ntfs-3g) (`ntfs-3g-progs`) | 2026.2.25-r0 | GPL-2.0-only | <https://www.tuxera.com/company/open-source/> |
| [hdparm](https://sourceforge.net/projects/hdparm/) | 9.65-r2 | BSD-2-Clause OR GPL-2.0-only | <https://sourceforge.net/projects/hdparm/> |
| [hd-idle](https://github.com/adelolmo/hd-idle) | 1.21-r11 | GPL-3.0-only | <https://github.com/adelolmo/hd-idle> |
| [libfuse](https://github.com/libfuse/libfuse) (`fuse3`) | 3.16.2-r1 | GPL-2.0-only AND LGPL-2.1-only | <https://github.com/libfuse/libfuse> |
| [apfs-fuse](https://github.com/sgan81/apfs-fuse) (amd64 and aarch64 only) | 0_git20230312-r0 | GPL-2-or-later | <https://github.com/sgan81/apfs-fuse> |
| [curl](https://curl.se/) | 8.14.1-r3 | curl | <https://curl.se/> |
| [jq](https://jqlang.github.io/jq/) | 1.7.1-r0 | MIT | <https://jqlang.github.io/jq/> |
| [FIGlet](http://www.figlet.org/) | 2.2.5-r3 | BSD-3-Clause | <http://www.figlet.org/> |
| [Python](https://www.python.org/) (`python3`) | 3.12.16-r0 | PSF-2.0 | <https://www.python.org/> |
| [pip](https://pip.pypa.io/) (`py3-pip`) | 24.3.1-r0 | MIT | <https://pip.pypa.io> |
| [pipx](https://github.com/pypa/pipx) | 1.7.1-r0 | MIT | <https://github.com/pypa/pipx> |
| [Poetry](https://python-poetry.org/) (installs the Python packages below) | 1.8.4-r0 | MIT | <https://python-poetry.org/> |

## Python packages

Installed by Poetry exactly as pinned in [`poetry.lock`](rootfs/usr/local/bin/poetry.lock). Mount It uses diskinfo to list drive labels at startup; the other packages are its dependencies.

| Package | Version | License | Source |
| --- | --- | --- | --- |
| [diskinfo](https://github.com/petersulyok/diskinfo) | 4.2.1 | MIT | <https://github.com/petersulyok/diskinfo> |
| [pyudev](https://github.com/pyudev/pyudev) | 0.24.5 | LGPL-2.1-or-later | <https://github.com/pyudev/pyudev> |
| [pySMART](https://github.com/truenas/py-SMART) | 1.4.3 | LGPL-2.1-or-later | <https://github.com/truenas/py-SMART> |
| [chardet](https://github.com/chardet/chardet) | 7.6.0 | 0BSD | <https://github.com/chardet/chardet> |
| [humanfriendly](https://github.com/xolox/python-humanfriendly) | 10.0 | MIT | <https://github.com/xolox/python-humanfriendly> |

`poetry.lock` also lists [pyreadline3](https://github.com/pyreadline3/pyreadline3) 3.5.6 (BSD), a Windows-only dependency of humanfriendly. It is never installed in Mount It.

## Supporting Alpine packages

Everything else the build installs: Alpine's base system, the packages added by the base image, and the dependencies of the main components. The versions are the ones the current build installs on amd64 (Alpine 3.21.9, 247 packages in total). Each build installs the latest Alpine 3.21 versions, so yours can be newer; armv7 builds leave out apfs-fuse and its dependencies.

<details>
<summary>220 packages</summary>

| Package | Version | License | Source |
| --- | --- | --- | --- |
| acl | 2.3.2-r1 | LGPL-2.1-or-later AND GPL-2.0-or-later | <https://savannah.nongnu.org/projects/acl> |
| acl-libs | 2.3.2-r1 | LGPL-2.1-or-later AND GPL-2.0-or-later | <https://savannah.nongnu.org/projects/acl> |
| agetty | 2.40.4-r1 | Public-Domain | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| alpine-baselayout | 3.6.8-r1 | GPL-2.0-only | <https://git.alpinelinux.org/cgit/aports/tree/main/alpine-baselayout> |
| alpine-baselayout-data | 3.6.8-r1 | GPL-2.0-only | <https://git.alpinelinux.org/cgit/aports/tree/main/alpine-baselayout> |
| alpine-keys | 2.5-r0 | MIT | <https://alpinelinux.org> |
| alpine-release | 3.21.9-r0 | MIT | <https://alpinelinux.org> |
| apk-tools | 2.14.6-r3 | GPL-2.0-only | <https://gitlab.alpinelinux.org/alpine/apk-tools> |
| avahi-libs | 0.8-r19 | LGPL-2.1-or-later | <https://www.avahi.org/> |
| bash | 5.2.37-r0 | GPL-3.0-or-later | <https://www.gnu.org/software/bash/bash.html> |
| blkid | 2.40.4-r1 | LGPL-1.0-only | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| brotli-libs | 1.1.1-r0 | MIT | <https://github.com/google/brotli> |
| busybox | 1.37.0-r14 | GPL-2.0-only | <https://busybox.net/> |
| busybox-binsh | 1.37.0-r14 | GPL-2.0-only | <https://busybox.net/> |
| c-ares | 1.34.9-r0 | MIT | <https://c-ares.org/> |
| ca-certificates-bundle | 20261020-r0 | MPL-2.0 AND MIT | <https://www.mozilla.org/en-US/about/governance/policies/security-group/certs/> |
| cfdisk | 2.40.4-r1 | GPL-2.0-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| cups-libs | 2.4.18-r0 | Apache-2.0 | <https://github.com/OpenPrinting/cups/> |
| dbus-libs | 1.14.10-r4 | AFL-2.1 OR GPL-2.0-or-later | <https://www.freedesktop.org/Software/dbus> |
| device-mapper-event-libs | 2.03.29-r1 | GPL-2.0-or-later AND LGPL-2.1-or-later AND BSD-2-Clause | <https://sourceware.org/lvm2/> |
| device-mapper-libs | 2.03.29-r1 | GPL-2.0-or-later AND LGPL-2.1-or-later AND BSD-2-Clause | <https://sourceware.org/lvm2/> |
| dmesg | 2.40.4-r1 | GPL-3.0-or-later AND GPL-2.0-or-later AND GPL-2.0-only AND GPL-1.0-only AND LGPL-2.1-or-later AND BSD-1-Clause AND BSD-3-Clause AND BSD-4-Clause-UC AND MIT AND Public-Domain | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| e2fsprogs-libs | 1.47.1-r1 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT | <https://e2fsprogs.sourceforge.net/> |
| eudev-libs | 3.2.14-r5 | GPL-2.0-or-later | <https://github.com/eudev-project/eudev> |
| flock | 2.40.4-r1 | MIT | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| fstrim | 2.40.4-r1 | GPL-2.0-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| fuse-common | 3.16.2-r1 | GPL-2.0-only AND LGPL-2.1-only | <https://github.com/libfuse/libfuse> |
| fuse3-libs | 3.16.2-r1 | GPL-2.0-only AND LGPL-2.1-only | <https://github.com/libfuse/libfuse> |
| gdbm | 1.24-r0 | GPL-3.0-or-later | <https://www.gnu.org/software/gdbm/> |
| gmp | 6.3.0-r2 | LGPL-3.0-or-later OR GPL-2.0-or-later | <https://gmplib.org/> |
| gnutls | 3.8.13-r0 | LGPL-2.1-or-later | <https://www.gnutls.org/> |
| hexdump | 2.40.4-r1 | BSD-4-Clause-UC | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| icu-data-en | 74.2-r1 | ICU | <https://icu.unicode.org/> |
| icu-libs | 74.2-r1 | ICU | <https://icu.unicode.org/> |
| inih | 58-r0 | BSD-3-Clause | <https://github.com/benhoyt/inih> |
| jansson | 2.14-r4 | MIT | <http://www.digip.org/jansson/> |
| kmod-libs | 33-r2 | LGPL-2.1-or-later | <http://git.kernel.org/?p=utils/kernel/kmod/kmod.git;a=summary> |
| ldb | 2.9.2-r0 | LGPL-3.0-or-later | <https://ldb.samba.org/> |
| libaio | 0.3.113-r2 | LGPL-2.1-or-later | <https://pagure.io/libaio> |
| libarchive | 3.8.10-r0 | BSD-2-Clause AND BSD-3-Clause AND Public-Domain | <https://libarchive.org/> |
| libattr | 2.5.2-r2 | LGPL-2.1-or-later | <https://savannah.nongnu.org/projects/attr> |
| libauth-samba | 4.20.6-r1 | GPL-3.0-or-later AND LGPL-3.0-or-later | <https://www.samba.org/> |
| libblkid | 2.40.4-r1 | LGPL-2.1-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| libbz2 | 1.0.8-r6 | bzip2-1.0.6 | <https://sourceware.org/bzip2/> |
| libcap-ng | 0.8.5-r0 | GPL-2.0-or-later AND LGPL-2.1-or-later | <https://people.redhat.com/sgrubb/libcap-ng/index.html> |
| libcap2 | 2.78-r0 | BSD-3-Clause OR GPL-2.0-only | <https://sites.google.com/site/fullycapable/> |
| libcom_err | 1.47.1-r1 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT | <https://e2fsprogs.sourceforge.net/> |
| libcrypto3 | 3.3.7-r2 | Apache-2.0 | <https://www.openssl.org/> |
| libcurl | 8.14.1-r3 | curl | <https://curl.se/> |
| libeconf | 0.6.3-r0 | MIT | <https://github.com/openSUSE/libeconf> |
| libexpat | 2.10.0-r0 | MIT | <https://libexpat.github.io/> |
| libfdisk | 2.40.4-r1 | LGPL-2.1-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| libffi | 3.4.7-r0 | MIT | <https://sourceware.org/libffi/> |
| libformw | 6.5_p20241006-r3 | X11 | <https://invisible-island.net/ncurses/> |
| libgcc | 14.2.0-r4 | GPL-2.0-or-later AND LGPL-2.1-or-later | <https://gcc.gnu.org> |
| libidn2 | 2.3.7-r0 | GPL-2.0-or-later OR LGPL-3.0-or-later | <https://www.gnu.org/software/libidn#libidn2> |
| libintl | 0.22.5-r0 | LGPL-2.1-or-later | <https://www.gnu.org/software/gettext/gettext.html> |
| liblastlog2 | 2.40.4-r1 | BSD-2-Clause | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| libldap | 2.6.8-r0 | OLDAP-2.8 | <https://www.openldap.org/> |
| libmount | 2.40.4-r1 | LGPL-2.1-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| libncursesw | 6.5_p20241006-r3 | X11 | <https://invisible-island.net/ncurses/> |
| libpanelw | 6.5_p20241006-r3 | X11 | <https://invisible-island.net/ncurses/> |
| libpsl | 0.21.5-r3 | MIT | <https://rockdaboot.github.io/libpsl> |
| libsasl | 2.1.28-r8 | BSD-3-Clause-Attribution AND BSD-4-Clause | <https://www.cyrusimap.org/sasl/> |
| libsmartcols | 2.40.4-r1 | LGPL-2.1-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| libsmbclient | 4.20.6-r1 | GPL-3.0-or-later AND LGPL-3.0-or-later | <https://www.samba.org/> |
| libssl3 | 3.3.7-r2 | Apache-2.0 | <https://www.openssl.org/> |
| libstdc++ | 14.2.0-r4 | GPL-2.0-or-later AND LGPL-2.1-or-later | <https://gcc.gnu.org> |
| libtasn1 | 4.21.0-r0 | LGPL-2.1-or-later | <https://www.gnu.org/software/gnutls/> |
| libunistring | 1.2-r0 | GPL-2.0-or-later OR LGPL-3.0-or-later | <https://www.gnu.org/software/libunistring/> |
| liburing | 2.8-r0 | LGPL-2.1-or-later OR MIT | <https://git.kernel.dk/cgit/liburing/> |
| libuuid | 2.40.4-r1 | BSD-3-Clause | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| libwbclient | 4.20.6-r1 | GPL-3.0-or-later AND LGPL-3.0-or-later | <https://www.samba.org/> |
| linux-pam | 1.6.1-r1 | BSD-3-Clause | <https://www.kernel.org/pub/linux/libs/pam> |
| lmdb | 0.9.33-r0 | OLDAP-2.8 | <https://symas.com/lmdb/> |
| logger | 2.40.4-r1 | BSD-4-Clause-UC | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| losetup | 2.40.4-r1 | GPL-2.0-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| lscpu | 2.40.4-r1 | GPL-2.0-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| lvm2-libs | 2.03.29-r1 | GPL-2.0-or-later AND LGPL-2.1-or-later AND BSD-2-Clause | <https://sourceware.org/lvm2/> |
| lz4-libs | 1.10.0-r0 | BSD-2-Clause AND GPL-2.0-or-later | <https://github.com/lz4/lz4> |
| lzo | 2.10-r5 | GPL-2.0-or-later | <https://www.oberhumer.com/opensource/lzo> |
| mcookie | 2.40.4-r1 | Public-Domain | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| mount | 2.40.4-r1 | GPL-3.0-or-later AND GPL-2.0-or-later AND GPL-2.0-only AND GPL-1.0-only AND LGPL-2.1-or-later AND BSD-1-Clause AND BSD-3-Clause AND BSD-4-Clause-UC AND MIT AND Public-Domain | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| mpdecimal | 4.0.0-r0 | BSD-2-Clause | <https://www.bytereef.org/mpdecimal/index.html> |
| musl | 1.2.5-r12 | MIT | <https://musl.libc.org/> |
| musl-utils | 1.2.5-r12 | MIT AND BSD-2-Clause AND GPL-2.0-or-later | <https://musl.libc.org/> |
| ncurses-terminfo-base | 6.5_p20241006-r3 | X11 | <https://invisible-island.net/ncurses/> |
| nettle | 3.10.2-r0 | GPL-2.0-or-later OR LGPL-3.0-or-later | <https://www.lysator.liu.se/~nisse/nettle/> |
| nghttp2-libs | 1.69.0-r0 | MIT | <https://nghttp2.org> |
| ntfs-3g-libs | 2026.2.25-r0 | GPL-2.0-only | <https://www.tuxera.com/company/open-source/> |
| oniguruma | 6.9.9-r0 | BSD-2-Clause | <https://github.com/kkos/oniguruma> |
| p11-kit | 0.26.2-r0 | BSD-3-Clause | <https://p11-glue.freedesktop.org/> |
| partx | 2.40.4-r1 | GPL-2.0-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| pipx-pyc | 1.7.1-r0 | MIT | <https://github.com/pypa/pipx> |
| poetry-pyc | 1.8.4-r0 | MIT | <https://python-poetry.org/> |
| popt | 1.19-r4 | MIT | <https://github.com/rpm-software-management/popt> |
| py3-argcomplete | 3.5.1-r0 | Apache-2.0 | <https://github.com/kislyuk/argcomplete> |
| py3-argcomplete-pyc | 3.5.1-r0 | Apache-2.0 | <https://github.com/kislyuk/argcomplete> |
| py3-build | 1.2.2-r1 | MIT | <https://github.com/pypa/build> |
| py3-build-pyc | 1.2.2-r1 | MIT | <https://github.com/pypa/build> |
| py3-cachecontrol | 0.14.1-r0 | Apache-2.0 | <https://github.com/psf/cachecontrol> |
| py3-cachecontrol-pyc | 0.14.1-r0 | Apache-2.0 | <https://github.com/psf/cachecontrol> |
| py3-certifi | 2024.8.30-r0 | MPL-2.0 | <https://pypi.org/project/certifi> |
| py3-certifi-pyc | 2024.8.30-r0 | MPL-2.0 | <https://pypi.org/project/certifi> |
| py3-cffi | 1.17.1-r1 | MIT | <https://cffi.readthedocs.io/> |
| py3-cffi-pyc | 1.17.1-r1 | MIT | <https://cffi.readthedocs.io/> |
| py3-charset-normalizer | 3.4.0-r0 | MIT | <https://github.com/ousret/charset_normalizer> |
| py3-charset-normalizer-pyc | 3.4.0-r0 | MIT | <https://github.com/ousret/charset_normalizer> |
| py3-cleo | 2.2.1-r0 | MIT | <https://github.com/python-poetry/cleo> |
| py3-cleo-pyc | 2.2.1-r0 | MIT | <https://github.com/python-poetry/cleo> |
| py3-click | 8.1.7-r2 | BSD-3-Clause | <https://click.palletsprojects.com> |
| py3-click-pyc | 8.1.7-r2 | BSD-3-Clause | <https://click.palletsprojects.com> |
| py3-colorama | 0.4.6-r5 | BSD-3-Clause | <https://pypi.org/project/colorama> |
| py3-colorama-pyc | 0.4.6-r5 | BSD-3-Clause | <https://pypi.org/project/colorama> |
| py3-cparser | 2.22-r1 | BSD-3-Clause | <https://github.com/eliben/pycparser> |
| py3-cparser-pyc | 2.22-r1 | BSD-3-Clause | <https://github.com/eliben/pycparser> |
| py3-crashtest | 0.4.1-r4 | MIT | <https://github.com/sdispater/crashtest> |
| py3-crashtest-pyc | 0.4.1-r4 | MIT | <https://github.com/sdispater/crashtest> |
| py3-cryptography | 44.0.0-r0 | Apache-2.0 OR BSD-3-Clause | <https://cryptography.io/> |
| py3-cryptography-pyc | 44.0.0-r0 | Apache-2.0 OR BSD-3-Clause | <https://cryptography.io/> |
| py3-distlib | 0.3.9-r0 | PSF-2.0 | <https://github.com/pypa/distlib> |
| py3-distlib-pyc | 0.3.9-r0 | PSF-2.0 | <https://github.com/pypa/distlib> |
| py3-dulwich | 0.21.7-r2 | GPL-2.0-or-later OR Apache-2.0 | <https://www.dulwich.io/> |
| py3-dulwich-pyc | 0.21.7-r2 | GPL-2.0-or-later OR Apache-2.0 | <https://www.dulwich.io/> |
| py3-fastjsonschema | 2.21.1-r0 | BSD-3-Clause | <https://horejsek.github.io/python-fastjsonschema/> |
| py3-fastjsonschema-pyc | 2.21.1-r0 | BSD-3-Clause | <https://horejsek.github.io/python-fastjsonschema/> |
| py3-filelock | 3.16.1-r0 | Unlicense | <https://github.com/tox-dev/py-filelock> |
| py3-filelock-pyc | 3.16.1-r0 | Unlicense | <https://github.com/tox-dev/py-filelock> |
| py3-idna | 3.10-r0 | BSD-3-Clause | <https://github.com/kjd/idna> |
| py3-idna-pyc | 3.10-r0 | BSD-3-Clause | <https://github.com/kjd/idna> |
| py3-importlib-metadata | 7.0.2-r1 | Apache-2.0 | <https://github.com/python/importlib_metadata> |
| py3-importlib-metadata-pyc | 7.0.2-r1 | Apache-2.0 | <https://github.com/python/importlib_metadata> |
| py3-installer | 0.7.0-r2 | MIT | <https://github.com/pypa/installer> |
| py3-installer-pyc | 0.7.0-r2 | MIT | <https://github.com/pypa/installer> |
| py3-jaraco.classes | 3.4.0-r1 | MIT | <https://github.com/jaraco/jaraco.classes> |
| py3-jaraco.classes-pyc | 3.4.0-r1 | MIT | <https://github.com/jaraco/jaraco.classes> |
| py3-jeepney | 0.8.0-r4 | MIT | <https://gitlab.com/takluyver/jeepney> |
| py3-jeepney-pyc | 0.8.0-r4 | MIT | <https://gitlab.com/takluyver/jeepney> |
| py3-keyring | 24.3.1-r1 | MIT | <https://github.com/jaraco/keyring> |
| py3-keyring-pyc | 24.3.1-r1 | MIT | <https://github.com/jaraco/keyring> |
| py3-lark-parser | 1.1.9-r1 | MIT | <https://github.com/lark-parser/lark> |
| py3-lark-parser-pyc | 1.1.9-r1 | MIT | <https://github.com/lark-parser/lark> |
| py3-more-itertools | 10.2.0-r1 | MIT | <https://github.com/more-itertools/more-itertools> |
| py3-more-itertools-pyc | 10.2.0-r1 | MIT | <https://github.com/more-itertools/more-itertools> |
| py3-msgpack | 1.0.8-r1 | Apache-2.0 | <https://msgpack.org/> |
| py3-msgpack-pyc | 1.0.8-r1 | Apache-2.0 | <https://msgpack.org/> |
| py3-packaging | 24.2-r0 | Apache-2.0 AND BSD-2-Clause | <https://pypi.org/project/packaging> |
| py3-packaging-pyc | 24.2-r0 | Apache-2.0 AND BSD-2-Clause | <https://pypi.org/project/packaging> |
| py3-parsing | 3.1.4-r0 | MIT | <https://github.com/pyparsing/pyparsing> |
| py3-parsing-pyc | 3.1.4-r0 | MIT | <https://github.com/pyparsing/pyparsing> |
| py3-pexpect | 4.9-r1 | ISC | <https://pexpect.readthedocs.io/en/stable/> |
| py3-pexpect-pyc | 4.9-r1 | ISC | <https://pexpect.readthedocs.io/en/stable/> |
| py3-pip-pyc | 24.3.1-r0 | MIT | <https://pip.pypa.io> |
| py3-pkginfo | 1.10.0-r1 | MIT | <https://code.launchpad.net/~tseaver/pkginfo> |
| py3-pkginfo-pyc | 1.10.0-r1 | MIT | <https://code.launchpad.net/~tseaver/pkginfo> |
| py3-platformdirs | 4.3.6-r0 | MIT | <https://github.com/platformdirs/platformdirs> |
| py3-platformdirs-pyc | 4.3.6-r0 | MIT | <https://github.com/platformdirs/platformdirs> |
| py3-poetry-core | 1.9.1-r0 | MIT | <https://github.com/python-poetry/poetry-core> |
| py3-poetry-core-pyc | 1.9.1-r0 | MIT | <https://github.com/python-poetry/poetry-core> |
| py3-poetry-plugin-export | 1.8.0-r0 | MIT | <https://github.com/python-poetry/poetry-plugin-export> |
| py3-poetry-plugin-export-pyc | 1.8.0-r0 | MIT | <https://github.com/python-poetry/poetry-plugin-export> |
| py3-ptyprocess | 0.7.0-r6 | ISC | <https://github.com/pexpect/ptyprocess> |
| py3-ptyprocess-pyc | 0.7.0-r6 | ISC | <https://github.com/pexpect/ptyprocess> |
| py3-pyproject-hooks | 1.2.0-r0 | MIT | <https://pyproject-hooks.readthedocs.io/> |
| py3-pyproject-hooks-pyc | 1.2.0-r0 | MIT | <https://pyproject-hooks.readthedocs.io/> |
| py3-rapidfuzz | 3.10.1-r0 | MIT | <https://github.com/maxbachmann/RapidFuzz> |
| py3-rapidfuzz-pyc | 3.10.1-r0 | MIT | <https://github.com/maxbachmann/RapidFuzz> |
| py3-requests | 2.33.1-r0 | Apache-2.0 | <https://requests.readthedocs.io/> |
| py3-requests-pyc | 2.33.1-r0 | Apache-2.0 | <https://requests.readthedocs.io/> |
| py3-requests-toolbelt | 1.0.0-r1 | Apache-2.0 | <https://github.com/requests/toolbelt> |
| py3-requests-toolbelt-pyc | 1.0.0-r1 | Apache-2.0 | <https://github.com/requests/toolbelt> |
| py3-secretstorage | 3.3.3-r3 | BSD-3-Clause | <https://github.com/mitya57/secretstorage> |
| py3-secretstorage-pyc | 3.3.3-r3 | BSD-3-Clause | <https://github.com/mitya57/secretstorage> |
| py3-setuptools | 70.3.0-r0 | MIT | <https://pypi.org/project/setuptools> |
| py3-setuptools-pyc | 70.3.0-r0 | MIT | <https://pypi.org/project/setuptools> |
| py3-shellingham | 1.5.4-r1 | MIT | <https://github.com/sarugaku/shellingham> |
| py3-shellingham-pyc | 1.5.4-r1 | MIT | <https://github.com/sarugaku/shellingham> |
| py3-tomlkit | 0.13.2-r0 | MIT | <https://github.com/sdispater/tomlkit> |
| py3-tomlkit-pyc | 0.13.2-r0 | MIT | <https://github.com/sdispater/tomlkit> |
| py3-trove-classifiers | 2024.10.21.16-r0 | Apache-2.0 | <https://github.com/pypa/trove-classifiers> |
| py3-trove-classifiers-pyc | 2024.10.21.16-r0 | Apache-2.0 | <https://github.com/pypa/trove-classifiers> |
| py3-urllib3 | 1.26.20-r1 | MIT | <https://github.com/urllib3/urllib3> |
| py3-urllib3-pyc | 1.26.20-r1 | MIT | <https://github.com/urllib3/urllib3> |
| py3-userpath | 1.9.2-r1 | MIT | <https://github.com/ofek/userpath> |
| py3-userpath-pyc | 1.9.2-r1 | MIT | <https://github.com/ofek/userpath> |
| py3-virtualenv | 20.28.0-r0 | MIT | <https://virtualenv.pypa.io/en/latest/> |
| py3-virtualenv-pyc | 20.28.0-r0 | MIT | <https://virtualenv.pypa.io/en/latest/> |
| py3-zipp | 3.17.0-r1 | MIT | <https://github.com/jaraco/zipp> |
| py3-zipp-pyc | 3.17.0-r1 | MIT | <https://github.com/jaraco/zipp> |
| pyc | 3.12.16-r0 | PSF-2.0 | <https://www.python.org/> |
| python3-pyc | 3.12.16-r0 | PSF-2.0 | <https://www.python.org/> |
| python3-pycache-pyc0 | 3.12.16-r0 | PSF-2.0 | <https://www.python.org/> |
| readline | 8.2.13-r0 | GPL-3.0-or-later | <https://tiswww.cwru.edu/php/chet/readline/rltop.html> |
| runuser | 2.40.4-r1 | GPL-2.0-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| samba-client-libs | 4.20.6-r1 | GPL-3.0-or-later AND LGPL-3.0-or-later | <https://www.samba.org/> |
| samba-common | 4.20.6-r1 | GPL-3.0-or-later AND LGPL-3.0-or-later | <https://www.samba.org/> |
| samba-common-server-libs | 4.20.6-r1 | GPL-3.0-or-later AND LGPL-3.0-or-later | <https://www.samba.org/> |
| samba-libs | 4.20.6-r1 | GPL-3.0-or-later AND LGPL-3.0-or-later | <https://www.samba.org/> |
| samba-util-libs | 4.20.6-r1 | GPL-3.0-or-later AND LGPL-3.0-or-later | <https://www.samba.org/> |
| scanelf | 1.3.8-r1 | GPL-2.0-only | <https://wiki.gentoo.org/wiki/Hardened/PaX_Utilities> |
| setarch | 2.40.4-r1 | GPL-3.0-or-later AND GPL-2.0-or-later AND GPL-2.0-only AND GPL-1.0-only AND LGPL-2.1-or-later AND BSD-1-Clause AND BSD-3-Clause AND BSD-4-Clause-UC AND MIT AND Public-Domain | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| setpriv | 2.40.4-r1 | GPL-2.0-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| sfdisk | 2.40.4-r1 | GPL-1.0-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| skalibs-libs | 2.14.3.0-r0 | ISC | <https://skarnet.org/software/skalibs/> |
| sqlite-libs | 3.48.0-r4 | blessing | <https://www.sqlite.org/> |
| ssl_client | 1.37.0-r14 | GPL-2.0-only | <https://busybox.net/> |
| talloc | 2.4.2-r1 | LGPL-3.0-or-later | <https://talloc.samba.org> |
| tdb-libs | 1.4.12-r0 | LGPL-3.0-or-later | <https://tdb.samba.org/> |
| tevent | 0.16.1-r0 | LGPL-3.0-or-later | <https://tevent.samba.org/> |
| tzdata | 2026e-r0 | Public-Domain | <https://www.iana.org/time-zones> |
| udev-init-scripts | 35-r1 | GPL-2.0-only | <https://gitweb.gentoo.org/repo/gentoo.git/tree/sys-fs/udev-init-scripts> |
| umount | 2.40.4-r1 | GPL-3.0-or-later AND GPL-2.0-or-later AND GPL-2.0-only AND GPL-1.0-only AND LGPL-2.1-or-later AND BSD-1-Clause AND BSD-3-Clause AND BSD-4-Clause-UC AND MIT AND Public-Domain | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| userspace-rcu | 0.14.1-r1 | LGPL-2.1-or-later | <https://liburcu.org/> |
| util-linux-misc | 2.40.4-r1 | GPL-3.0-or-later AND GPL-2.0-or-later AND GPL-2.0-only AND GPL-1.0-only AND LGPL-2.1-or-later AND BSD-1-Clause AND BSD-3-Clause AND BSD-4-Clause-UC AND MIT AND Public-Domain | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| utmps-libs | 0.1.2.3-r2 | ISC | <https://skarnet.org/software/utmps/> |
| uuidgen | 2.40.4-r1 | GPL-1.0-only | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| wipefs | 2.40.4-r1 | GPL-2.0-or-later | <https://git.kernel.org/cgit/utils/util-linux/util-linux.git> |
| xz-libs | 5.8.4-r0 | GPL-2.0-or-later AND 0BSD AND Public-Domain AND LGPL-2.1-or-later | <https://tukaani.org/xz/> |
| zlib | 1.3.2-r1 | Zlib | <https://zlib.net/> |
| zstd-libs | 1.5.6-r2 | BSD-3-Clause OR GPL-2.0-or-later | <https://facebook.github.io/zstd/> |

</details>

## Home Assistant logo

Mount It's [icon](icon.png), [logo](logo.png) and [banner](../.asset/mountit/banner.png) include the Home Assistant logo, which is the property of the [Open Home Foundation](https://www.openhomefoundation.org/). It is used under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License](https://creativecommons.org/licenses/by-nc-sa/4.0/), as published in the [Home Assistant assets repository](https://github.com/home-assistant/assets), combined with a drawing of a hard drive made in [draw.io](https://www.drawio.com/). These images, including their source [mount-it.drawio](../.asset/mountit/mount-it.drawio), are shared under the same license.

"Home Assistant" and the Home Assistant logo are trademarks of the Open Home Foundation. Mount It is a community project and is not affiliated with or endorsed by the Open Home Foundation or Nabu Casa.

## GPL and LGPL components

Several components are licensed under the GNU General Public License or the GNU Lesser General Public License, including Samba (GPL-3.0-or-later and LGPL-3.0-or-later), bash (GPL-3.0-or-later), hd-idle (GPL-3.0-only), util-linux, e2fsprogs, NTFS-3G, eudev, btrfs-progs and exfatprogs (GPL-2.0), and pyudev and pySMART (LGPL-2.1-or-later). Mount It does not distribute builds of them: your device downloads them from Alpine's repository and PyPI when it builds the app. Their source code is available from the upstream projects linked above and, for every Alpine package, from [Alpine's aports repository](https://gitlab.alpinelinux.org/alpine/aports/-/tree/3.21-stable).
