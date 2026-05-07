# Mount It

Automatically detects and mounts external USB/SATA drives, then exposes them as
Home Assistant network storage (CIFS) via the Supervisor Mounts API.

## How it works

1. On startup, detected drives are mounted inside the addon at `/mnt/<label>`
2. A minimal Samba server exposes each mount as a private share
3. The HA Supervisor registers each share as network storage (Settings → Storage)
4. On shutdown, HA network mounts are cleanly removed and drives unmounted

Hot-plugging a drive while the addon is running will automatically mount and register
it (if `automount_on_plugin` is enabled).

## Configuration

| Option | Default | Description |
|---|---|---|
| `mount_unlabeled` | `false` | Mount drives that have no filesystem label |
| `automount_on_plugin` | `true` | Automatically mount drives when plugged in |
| `specific_label` | `""` | If set, only mount this label at startup (hot-plug still mounts all) |
| `mount_location` | `media` | Where to expose drives: `media`, `share`, or `backup` |
| `hdd_idle_seconds` | `0` | Spin down drives after N seconds idle (0 = disabled) |

## Folder Mounts (Advanced)

You can map specific subfolders of a mounted drive to a different HA storage location.
This is useful when, for example, you store both media files and HA backups on the same drive.

**Example:** Mount `DriveHDD` drive to `media`, and also expose `DriveHDD/ha_backup` to `backup`:

```yaml
folder_mounts:
  - drive: DriveHDD
    folder: ha_backup
    location: backup
```

Each folder mount:

- Requires the parent drive to be mounted first
- The folder path must already exist on the drive
- Is registered in HA as a separate network storage entry
- Appears in HA as `<DriveLabel>_<FolderPath>` (e.g., `DriveHDD_ha_backup`)

## Supported filesystems

| Filesystem | Support |
| --- | --- |
| ext2 / ext3 / ext4 | Full |
| NTFS | Full (via ntfs3) |
| Btrfs | Full |
| XFS | Full |
| exFAT / FAT32 / VFAT | Experimental (no ACL support) |
| APFS | Read-only, experimental (aarch64/amd64 only) |

## Requirements

- Home Assistant OS
- Protection mode **disabled** in the addon settings
