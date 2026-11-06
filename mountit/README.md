# Mount It — Home Assistant Addon

![Mount It](https://raw.githubusercontent.com/EnderDragonEP/HomeAssistant-Apps/main/.asset/mountit/banner.png)

Automatically detects and mounts external USB/SATA drives, then exposes them as Home Assistant network storage via the Supervisor Mounts API.

Icon & banner is made in [draw.io](https://github.com/jgraph/drawio)

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
![Supports armv7 Architecture][armv7-shield]

> [!NOTE]
> **Home Assistant can now mount local drives itself.** <p> Since Home Assistant 2026.11.0, you can add a USB or internal drive under **Settings → System → Storage → Add storage → Local disk**, without any app ([documentation](https://www.home-assistant.io/common-tasks/os/#local-disk-storage)). If you have one drive that stays connected and is used for one thing, the built-in feature may be all you need. See [Reasons to keep using Mount It](#reasons-to-keep-using-mount-it) for what Mount It still adds.

## Features

- Auto-detects labeled drives on startup and hot-plug
- Exposes drives as network storage in **Settings → Storage**
- Optional support for unlabeled drives
- Configurable storage location (`media`, `share`, or `backup`)
- Advanced folder mapping: expose subfolders to different HA locations
- HDD idle power-down support
- Configurable file activity logging for troubleshooting
- Automation events when drives are mounted, removed, or fail to mount
- Clean shutdown: deregisters mounts and unmounts drives

## Automation example

Start Frigate only after Mount It has mounted its drives, so recordings never land on the
wrong disk. Turn off **Start on boot** for Frigate and add this automation:

```yaml
alias: Start Frigate when drives are ready
triggers:
  - trigger: event
    event_type: mountit_ready
actions:
  - action: hassio.app_start
    data:
      app: ccab4aaf_frigate
```

See [DOCS.md](DOCS.md#automations) for all events and their data.

## Supported filesystems

ext2/3/4, NTFS, Btrfs, XFS, exFAT/FAT32, APFS (read-only)

## Installation

1. Add this repository to your HA addon store
2. Install **Mount It**
3. Disable **Protection Mode** in the addon settings
4. Start the addon

## Documentation

See [DOCS.md](DOCS.md) for full configuration reference.

The open-source components Mount It is built on, and the license of the Home Assistant logo in its icon, are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[armv7-shield]: https://img.shields.io/badge/armv7-yes-green.svg

## Reasons to keep using Mount It

- **Fully automatic:** Mount It mounts labelled drives at startup and as soon as they're plugged in. With the built-in feature, you add each disk by hand, and a reconnected disk can take up to 15 minutes to come back unless you reload it from the repair.
- **Recovers NTFS drives after an unsafe unplug:** an NTFS drive that is unplugged or loses power while in use is left marked as dirty, and the built-in feature can't mount it again until it has been repaired with chkdsk on Windows. Mount It clears the dirty flag and mounts it again, so apps such as Frigate can carry on (it still recommends checking the drive with chkdsk later).
- **More file systems:** XFS and APFS (read-only) are supported, which the built-in feature doesn't list.
- **One drive, several uses:** the built-in feature mounts each drive in one place only, for a single use (media, share or backup), so you can't use the same drive for both media and backups. With folder mounts, Mount It can: for example, the whole drive as media and its `ha_backup` folder as backup storage.
- **Automation events:** start apps such as Frigate when the drives are ready, stop them before Mount It shuts down, or get notified when a drive is removed or fails to mount.
- **Extras:** hard drive spin-down and a file activity log.

Use one or the other for a given drive, not both.

## Disclaimer

This application is built specifically for Home Assistant OS and is not guaranteed to function properly on other installation types. Please do your research before installation. If you have any questions, please submit a issue report with logs attached.
