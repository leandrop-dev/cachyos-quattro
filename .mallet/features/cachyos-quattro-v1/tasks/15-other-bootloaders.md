# Task: other-bootloaders
Status: deferred (phase 2 roadmap, 2026-10-21)
Deps: 13

## Goal
Extend support to CachyOS on systemd-boot and GRUB, with and without LUKS (phase 2).

## Steps
1. Re-run `/mallet:plan-feature` for a `bootloaders-phase2` feature that splits this task into sub-tasks; the items below are its starting scope.
2. Write `package-nolimine/PKGBUILD` for `cachyos-quattro-nolimine`: `provides=('limine=9999' 'limine-mkinitcpio-hook=9999' 'limine-snapper-sync=9999' 'limine-entry-tool')`, `conflicts=('limine' 'limine-mkinitcpio-hook' 'limine-snapper-sync')`, empty package, installed only when `cq_bootloader` is `systemd-boot` or `grub` (satisfies `omarchy`'s hard dependencies without touching the ESP; source: Robert0X in #74).
3. Extend `ledger/files.tsv` handling: on non-Limine systems `omarchy_hooks.conf` NoExtract becomes mandatory (its `btrfs-overlayfs` hook ships with `limine-mkinitcpio-hook`, which the stub package replaces).
4. Extend `lib/detect.sh` preflight to accept `systemd-boot` and `grub`; extend `verify` with bootloader-specific checks (`bootctl list` entries unchanged; `grub-mkconfig` titles use CachyOS identity; no Limine EFI entry in `efibootmgr`).
5. Replace `limine-mkinitcpio` in install/uninstall/recover with a `cq_rebuild_initramfs` helper that runs `limine-mkinitcpio`, `mkinitcpio -P` or the systemd-boot/GRUB path as detected.
6. Add golden images `sdboot-luks`, `sdboot-plain`, `grub-luks`, `grub-plain` to `docs/testing.md` and run every task-13 scenario on them.

## Notes
Out of v1. GRUB evidence from #74 (Robert0X): `grub-mkconfig` reads `/etc/os-release` for menu titles; a 196 MiB ESP shared with Windows must not receive a Limine EFI entry.
