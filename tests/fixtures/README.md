# Test fixtures

Each directory is a fake root that `mkroot` (in `tests/unit/helpers.bash`) copies into
`$CQ_ROOT` for one test. Both roots model a stock CachyOS install with no desktop,
on Limine, with btrfs; `cachyos-limine-luks` adds a LUKS root unlocked by `sd-encrypt`.

The development machine runs a desktop that customises its boot configuration, so its
installer-written files are not used. Every file's source is listed below.
Rows marked **synthetic** are replaced with copies from the golden VM images in task 03.

| File | Source |
|---|---|
| `etc/os-release` | A CachyOS host's `/etc/os-release` (not owned by any package) |
| `etc/nsswitch.conf` | Package `filesystem` 2025.10.12-1, unmodified |
| `etc/mkinitcpio.conf` (plain) | Package `mkinitcpio` 42.2-1, unmodified |
| `etc/mkinitcpio.conf` (luks) | Package `mkinitcpio` 42.2-1 with `sd-encrypt` inserted before `filesystems` — **synthetic** |
| `etc/limine-entry-tool.conf` | Package `limine-mkinitcpio-hook` 1.40.0-1, unmodified |
| `etc/default/limine` | **Synthetic** — placeholder values, cmdline matches `proc/cmdline` |
| `etc/pacman.conf` | A CachyOS host's `/etc/pacman.conf` (x86-64-v3 repos) with a third-party repo section removed |
| `etc/pacman.d/mirrorlist` | Package `pacman-mirrorlist` 20260610-1 with the first two `Server` lines uncommented |
| `etc/pacman.d/cachyos-mirrorlist` | Package `cachyos-mirrorlist` 27-1, unmodified |
| `etc/pacman.d/cachyos-v3-mirrorlist` | First three ranked `Server` lines from a CachyOS host |
| `proc/cmdline` | **Synthetic** — all-zero UUIDs |
