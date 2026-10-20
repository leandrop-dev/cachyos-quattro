# Task: guard-package
Status: pending
Deps: 02, 04

## Goal
Build the cachyos-quattro pacman package with the NoExtract drop-in, the pacman-guard mask, the early identity-restore hook and the command stubs.

## Steps
1. Write `package/PKGBUILD`: `pkgname=cachyos-quattro`, `arch=(any)`, `depends=(bash pacman coreutils)`, `backup=(etc/pacman.d/cachyos-quattro.conf)`, `install=cachyos-quattro.install`; `package()` installs:
   - `etc/pacman.d/cachyos-quattro.conf` — generated in `build()` by `tools/gen-noextract ledger/files.tsv`: one `NoExtract = <path>` line per `noextract` row, exact paths only;
   - `etc/pacman.d/hooks/00-omarchy-update-guard.hook` as a symlink to `/dev/null` (alpm-hooks(5) masking);
   - `usr/share/libalpm/hooks/05-cachyos-quattro-identity.hook`;
   - `usr/lib/cachyos-quattro/restore-identity`;
   - `usr/local/bin/<stub>` for each stub in step 4, all symlinks to `usr/lib/cachyos-quattro/stub`;
   - `usr/share/cachyos-quattro/ledger/*.tsv` copied from `ledger/`.
2. Write `package/hooks/05-cachyos-quattro-identity.hook`: `[Trigger] Operation=Install, Operation=Upgrade, Type=Package, Target=omarchy-settings, Target=omarchy-settings-dev`; `[Action] When=PostTransaction, Exec=/usr/lib/cachyos-quattro/restore-identity`. The `05-` prefix sorts before every initramfs hook (`60-*`, `80-limine-efi-deploy`, `90-mkinitcpio-install`, `cachyos-plymouth-initramfs`).
3. Write `package/libexec/restore-identity`: for each of `etc/os-release` and `etc/nsswitch.conf`, copy `${CQ_ROOT}/var/lib/cachyos-quattro/identity/<file>` over `${CQ_ROOT}/<file>` with mode 0644 when the saved copy exists and differs; log each restore to `${CQ_ROOT}/var/log/cachyos-quattro.log`; exit 0 with a warning when no saved copy exists.
4. Write `package/libexec/stub`: reads `basename "$0"`, prints why the command is blocked on CachyOS and what to do instead (from a `case` table), exits 1; `CQ_ALLOW_DANGEROUS=1` execs `/usr/bin/<name> "$@"`. Stubbed names: `omarchy-refresh-limine`, `omarchy-refresh-pacman`, `omarchy-version-channel`, `omarchy-upgrade-to-quattro`, `omarchy-setup-direct-boot`, `omarchy-hibernation-setup`, `omarchy-hibernation-remove`, `omarchy-system-factory-reset`, `omarchy-reinstall-configs`. `omarchy-snapshot` gets its own wrapper: `create` execs `/usr/bin/omarchy-snapshot create`, `restore` is refused with directions to the Limine snapshot menu. Before writing, confirm each name exists in `build/ledger/4.0.6` (the CLI router may expose `omarchy channel set` through `omarchy-version-channel`).
5. Write `package/cachyos-quattro.install` with `post_install`/`post_upgrade` printing whether `/etc/pacman.conf` contains `Include = /etc/pacman.d/cachyos-quattro.conf` in `[options]` (the CLI adds it in task 10; the package never edits pacman.conf).
6. Write `tests/unit/identity.bats`: restore-identity restores a modified os-release and nsswitch.conf in a fixture root; leaves files alone when identical; warns and exits 0 with no saved copy.
7. Write `tests/unit/stubs.bats`: each stub exits 1 with its message; `CQ_ALLOW_DANGEROUS=1` execs the target (fixture `/usr/bin` via `CQ_ROOT` + PATH); every stub name is present in the ledger's `omarchy` file list.
8. Write `tests/unit/noextract.bats`: the generated drop-in contains exactly the `noextract` rows, no globs, and `pacman-conf --config <tmp pacman.conf with Include> NoExtract` lists them.
9. `cd package && makepkg -f` builds; `namcap` (if installed) reports no errors; `make check` passes.

## TDD Checklist
- [ ] Write failing tests (identity, stubs, noextract)
- [ ] Confirm tests fail (red)
- [ ] Implement
- [ ] Confirm tests pass (green)
- [ ] Confirm no regressions

## Notes
Verified during planning: `Include` inside `[options]` accumulates NoExtract entries (`pacman-conf` test). The etc-overrides source files under `usr/share/omarchy/etc-overrides/` must never be NoExtract'd, because `.INSTALL` runs `rm -f /etc/os-release` before `cp -f`. Stubs are UX; Omarchy calls some commands by absolute path (`omarchy-refresh-sddm` → `$OMARCHY_PATH/bin/omarchy-plymouth-set`), which the stubs do not intercept by design.
