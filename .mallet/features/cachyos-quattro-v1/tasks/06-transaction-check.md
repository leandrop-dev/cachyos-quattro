# Task: transaction-check
Status: done
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
- [x] Write failing test
- [x] Confirm test fails (red)
- [x] Implement
- [x] Confirm test passes (green)
- [x] Confirm no regressions

## Notes
This is the council's fail-closed answer to exact-path NoExtract missing a renamed or new drop-in. A path NoExtract'd by the ledger still appears as a hook target; it is in `files.tsv` and passes. Confirm in the VM (task 13) that `Type = Path` triggers fire for NoExtract'd paths and for paths in packages pulled in as dependencies.

As built (2026-10-21):
- One hook with two kinds of trigger: a `Type = Package`, `Target = *` trigger passes the transaction's package names and the `Type = Path` triggers pass its boot-sensitive paths. With `NeedsTargets`, pacman passes the targets of every matching trigger on stdin; txn-check splits them on `/`. A Path-only hook could not tell which package ships a path, and listing every cached Omarchy package on each run would be slow.
- A package counts as Omarchy's when `pacman -Sp -dd --print-format '%r|%n|%f'` resolves it to the `[omarchy]` repo (the first repo that has it wins, so the 27 overlap packages CachyOS wins are skipped), or when its name starts with `omarchy` and no repo has it. `-Sp` works while pacman holds the database lock (checked against a copy of the sync databases with `db.lck` present). Only those packages are listed with `bsdtar -tf` from the cache.
- Fails closed when an Omarchy package is not in the cache, is installed with `pacman -U` (read from `/proc/$PPID/cmdline`, as Omarchy's own guard does), or is an `omarchy*` package in no repo; also when the ledger is missing or a pacman query fails. `CQ_TXN_ALLOW=1` re-runs the check in report mode and continues.
- Path targets go beyond step 1: also `etc/mkinitcpio.conf`, `etc/modprobe.d/*`, `usr/lib/modprobe.d/*` (both go into the initramfs through `modconf`), `usr/lib/initcpio/*`, `usr/lib/kernel/*`, `usr/lib/sysctl.d/*`, `usr/lib/tmpfiles.d/*`, `etc/systemd/{system,user}.conf.d/*`, `etc/fstab`, `etc/crypttab`, `etc/vconsole.conf`, `usr/share/libalpm/hooks/*` (a new pacman hook runs as root). Directory entries are ignored.
- The check is path-based: a reviewed path whose content changes passes. Content changes are the upstream-diff CI's job (task 12).
- `txn-check.bats` also checks that every 4.0.6 file under a hook target is in `files.tsv`, so a stock 4.0.6 install does not abort; confirmed to fail when a row is removed.
- `omarchy.files` from pkgs.omarchy.org shows 15 other `[omarchy]` packages shipping files under these paths (docs/conflicts.md #17); none is in the base package list.
- `tests/vm/scenarios/txn-check.sh` (with `tests/vm/guest/mkfakepkg.sh`) serves fake `omarchy-settings` packages from a local `file://` `[omarchy]` repo on limine-plain. Confirmed there: the hook receives both package names and paths; pacman copies `file://` packages into the cache before PreTransaction hooks; the abort comes before snap-pac's pre snapshot (no new snapshot); NoExtract keeps `omarchy_hooks.conf` off disk; `pacman -U` is refused; `CQ_TXN_ALLOW=1` reaches the hook through `sudo env`. It also exercises the task 05 identity hook end to end: the fake package's `.INSTALL` replaces `/etc/os-release` and the 05- hook restores it.
- Result (task 13, 2026-10-21): Path triggers fire for dependency packages' files; they do not fire for NoExtract'd paths. txn-check uses the latter: a `noextract` path among its targets means the Include is not in effect, and it aborts.
