# Changelog

## 1.3.2

- Fix drives with spaces in their label getting a different name when plugged in than at
  startup (e.g. `ExternelTestDrive` instead of `External_Test_Drive`). Plugged-in
  drives now always use the startup name, and Specific Label now matches them

## 1.3.1

- Never replace or remove your own network storage entries: if a drive has the same name as
  an existing entry (for example a NAS), Mount It now skips it instead of overwriting it
- Folder mounts are removed when their drive is unplugged and come back when it is plugged in again
- Log a warning when a hot-plugged drive could not be added to network storage
- Fix the Specific Label option description, which still said it only applied at startup

## 1.3.0

- Add Home Assistant events for automations: `mountit_ready`, `mountit_drive_mounted`,
  `mountit_drive_removed`, `mountit_mount_failed` and `mountit_ntfs_repaired`
- Startup events are held until Home Assistant is running, so they still arrive after a host reboot
- Use `mountit_ready` to start apps such as Frigate only after the drives are mounted (#8)
- See the Automations section of the documentation for event data and examples

## 1.2.3

- Fix drives getting stuck on the host after stopping or updating the app: network storage
  is now removed while Samba is still running (#6)
- Give services more time to shut down cleanly

## 1.2.2

- Fix file and folder names showing up mangled (e.g. `ABCDE~1`) over the network share (#10)

## 1.2.1

- Roll back to the 1.2.0 mount logic. The registration and recovery rework released as
  1.3.0 has been withdrawn

## 1.2.0

- Add an optional `name` for folder mounts to choose their network storage name
- Replace the file activity log toggle with `file_activity_detail`: `off`, `basic` or `detailed`
- Existing file activity settings are migrated automatically

## 1.1.1

- Add timestamps to file activity log entries

## 1.1.0

- Add optional file activity logging for troubleshooting access to the shares

## 1.0.2

- Support NTFS alternate data streams over Samba
- `specific_label` now also applies to hot-plugged drives
- Warn when several partitions share the same label
- Samba only listens on the app's own address
- Drop unneeded permissions and folder mappings, and tighten the AppArmor profile
- Remove the unused NetBIOS service

## 1.0.1

- Run `ntfsfix` and retry when an NTFS drive fails to mount because it was not ejected safely
- Fix stale network storage entries not being removed before re-registering

## 1.0.0

- Initial release
