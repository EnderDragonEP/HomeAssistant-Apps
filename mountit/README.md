# Mount It — Home Assistant Addon

![Mount It](icon.png)

Automatically detects and mounts external USB/SATA drives, then exposes them as
Home Assistant network storage via the Supervisor Mounts API.

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
![Supports armv7 Architecture][armv7-shield]

## Features

- Auto-detects labeled drives on startup and hot-plug
- Exposes drives as network storage in **Settings → Storage**
- Optional support for unlabeled drives
- Configurable storage location (`media`, `share`, or `backup`)
- Advanced folder mapping: expose subfolders to different HA locations
- HDD idle power-down support
- Clean shutdown: deregisters mounts and unmounts drives

## Supported filesystems

ext2/3/4, NTFS, Btrfs, XFS, exFAT/FAT32, APFS (read-only)

## Installation

1. Add this repository to your HA addon store
2. Install **Mount It**
3. Disable **Protection Mode** in the addon settings
4. Start the addon

## Documentation

See [DOCS.md](DOCS.md) for full configuration reference.

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[armv7-shield]: https://img.shields.io/badge/armv7-yes-green.svg
