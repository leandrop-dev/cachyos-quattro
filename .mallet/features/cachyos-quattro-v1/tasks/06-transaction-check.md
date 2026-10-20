# Task: transaction-check
Status: pending
Deps: 05

## Goal
Abort any pacman transaction in which an Omarchy package would install an unreviewed file in a boot-sensitive path.

## Steps
1. Write `package/hooks/04-cachyos-quattro-txn-check.hook`: `[Trigger] Operation=Install, Operation=Upgrade, Type=Path`, with `Target =` lines `etc/mkinitcpio.conf.d/*`, `etc/mkinitcpio.d/*`, `etc/limine-entry-tool.d/*`, `etc/default/limine`, `etc/pacman.conf`, `etc/pacman.d/*`, `etc/sysctl.d/*`, `etc/tmpfiles.d/*`, `etc/systemd/zram-generator.conf`, `usr/lib/systemd/zram-generator.conf.d/*`, `etc/os-release`, `usr/lib/os-release`, `etc/kernel/*`, `boot/*`; `[Action] When=PreTransaction, Exec=/usr/lib/cachyos-quattro/txn-check, NeedsTargets, AbortOnFail`.
2. Write `package/libexec/txn-check`: reads target paths on stdin; builds the set of paths shipped by the Omarchy packages in this transaction by listing (`bsdtar -tf`) the newest `omarchy*-*.pkg.tar.zst` files in `pacman-conf CacheDir` that match `pacman -Sp --print-format '%n %v'` of `omarchy omarchy-settings`; for each target path that an Omarchy package ships and that is not in `/usr/share/cachyos-quattro/ledger/files.tsv`, print `cachyos-quattro: unreviewed Omarchy file <path> (package <pkg>)` and exit 1. Paths from non-Omarchy packages pass. If the Omarchy package files cannot be found in the cache (e.g. `pacman -U`), fail closed for any target path not owned by an installed non-Omarchy package (`pacman -Qoq`) and not in the ledger, with a message naming `CQ_TXN_ALLOW=1` as the explicit override.
3. Add both files to `package/PKGBUILD`.
4. Write `tests/unit/txn-check.bats` using fixture package tarballs built in the test (`bsdtar -cf` of a fake `omarchy-settings` tree): a ledger-known path passes; a new `etc/mkinitcpio.conf.d/omarchy_new.conf` aborts; a renamed `omarchy_hooks2.conf` aborts; a CachyOS-owned path passes; missing cache fails closed; `CQ_TXN_ALLOW=1` passes with a warning.
5. `make check` passes; `makepkg -f` builds.

## TDD Checklist
- [ ] Write failing test
- [ ] Confirm test fails (red)
- [ ] Implement
- [ ] Confirm test passes (green)
- [ ] Confirm no regressions

## Notes
This is the council's fail-closed answer to exact-path NoExtract missing a renamed or new drop-in. A path NoExtract'd by the ledger still appears as a hook target; it is in `files.tsv` and passes. Confirm in the VM (task 13) that `Type = Path` triggers fire for NoExtract'd paths and for paths in packages pulled in as dependencies.
