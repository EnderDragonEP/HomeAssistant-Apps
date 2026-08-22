# Mount It

Automatically detects and mounts external USB/SATA drives, then exposes them as
Home Assistant network storage (CIFS) via the Supervisor Mounts API.

## How it works

1. On startup, detected drives are mounted inside the addon at `/mnt/<label>`
2. A minimal Samba server exposes each mount as a private share
3. The HA Supervisor registers each share as network storage (Settings → Storage)
4. Mount It verifies each registration and automatically retries transient failures
5. On shutdown, folder entries are removed before their parent drive, then drives are unmounted

Hot-plugging a drive while the addon is running will automatically mount and register
it (if `automount_on_plugin` is enabled).

Mount It creates a private random Samba credential on first start and stores it in
the addon's protected data directory. Reusing that credential across restarts lets
existing Home Assistant mounts reconnect safely. It is not a user-facing password.

## Configuration

| Option | Default | Description |
|---|---|---|
| `mount_unlabeled` | `false` | Mount drives that have no filesystem label |
| `automount_on_plugin` | `true` | Automatically mount drives when plugged in |
| `specific_label` | `""` | If set, only this drive label is mounted (applies to startup and hot-plug) |
| `mount_location` | `media` | Where to expose drives: `media`, `share`, or `backup` |
| `hdd_idle_seconds` | `0` | Spin down drives after N seconds idle (0 = disabled). The HAOS system disk is always excluded. |
| `file_activity_detail` | `off` | File activity logging level: `off`, `basic`, or `detailed` |

## File Activity Log

Set `file_activity_detail` to `basic` or `detailed` to record file operations in
the addon log (**Settings → Add-ons → Mount It → Log**). Each operation is
written as a single line:

```txt
2026/08/10 21:04:11|172.30.32.1|DriveHDD|create_file|ok|0x80000000|file|open|/mnt/DriveHDD/Movies/clip.mkv
2026/08/10 21:04:19|172.30.32.1|DriveHDD|renameat|ok|/mnt/DriveHDD/a.txt|/mnt/DriveHDD/b.txt
2026/08/10 21:04:25|172.30.32.1|DriveHDD|unlinkat|fail|/mnt/DriveHDD/locked.bin
```

The fields are `timestamp | client IP | share | operation | ok/fail | details`.
Both successful and failed operations are recorded.

| Detail | Records |
| --- | --- |
| `off` | File activity logging is disabled |
| `basic` | Share connects/disconnects, file opens and creations, deletes, renames, and new folders |
| `detailed` | Everything in `basic`, plus closes, truncations, permission/attribute/ACL changes, and every individual read and write |

### Notes

- The shares are mounted by Home Assistant itself, so the client IP is your HA host.
- `detailed` can produce thousands of lines while copying a large file and may slow transfers.
- The log is not persisted by the addon; it lives in the addon's container log.
- Samba 4.14 or newer is required. On older versions, activity logging stays off.

## Folder Mounts (Advanced)

You can map specific subfolders of a mounted drive to a different HA storage location.
This is useful when, for example, you store both media files and HA backups on the same drive.

**Example:** Mount `DriveHDD` drive to `media`, and also expose `DriveHDD/ha_backup` to `backup`:

```yaml
folder_mounts:
  - name: CameraMedia
    drive: DriveHDD
    folder: ha_backup
    location: backup
```

Each folder mount:

- Requires the parent drive to be mounted first
- The folder path must already exist and resolve within the selected drive
- Is registered in HA as a separate network storage entry
- Can use an optional `name` containing letters, numbers, and underscores
- Appears in HA using `name`, or `<DriveLabel>_<FolderPath>` when `name` is omitted
- Is restored together with its parent drive after a hot-plug event

## Registration recovery

Mount It checks the live Supervisor state instead of deleting and recreating healthy
network storage on every start. Failed entries are reloaded or refreshed, and a
background recovery monitor retries temporary Supervisor/systemd failures once per
minute. A success message is only written after Supervisor reports the entry as
active. Entries with the same name but a different server or share are treated as
external and are never overwritten or removed.

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
