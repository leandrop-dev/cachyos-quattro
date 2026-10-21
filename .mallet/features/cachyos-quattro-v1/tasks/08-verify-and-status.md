# Task: verify-and-status
Status: done
Deps: 05

## Goal
Verify every protection after each transaction and on demand through `cachyos-quattro status`.

## Steps
1. Write `package/libexec/verify` (exit 0 all pass, 1 any fail, prints one line per check `ok|FAIL|warn <check>: <detail>`), reading baselines from `${CQ_ROOT}/var/lib/cachyos-quattro/baseline/`:
   - `pacman-include`: `pacman-conf NoExtract` contains every `noextract` path in the ledger (catches a pacdiff merge that dropped the Include);
   - `noextract-absent`: none of those paths exist on disk;
   - `guard-mask`: `/etc/pacman.d/hooks/00-omarchy-update-guard.hook` is a symlink to `/dev/null`;
   - `hooks`: effective HOOKS (subshell sourcing `/etc/mkinitcpio.conf` then `/etc/mkinitcpio.conf.d/*.conf` in sort order) equals `baseline/hooks`; on LUKS roots it contains `sd-encrypt` (or `encrypt` when the baseline cmdline uses `cryptdevice=`);
   - `initramfs`: for each initramfs image under `/boot` (CachyOS Limine layout `/boot/<machine-id>/<kernel>/initramfs*`), `lsinitcpio` lists `systemd-cryptsetup` on LUKS roots;
   - `limine`: `TARGET_OS_NAME`, `ENABLE_UKI`, `BOOT_ORDER`, `MAX_SNAPSHOT_ENTRIES` from `load_config` in `/usr/lib/limine/limine-common-functions` (subshell, as root) equal `baseline/limine`;
   - `identity`: `/etc/os-release` has `ID=cachyos`; `/etc/nsswitch.conf` equals the saved copy;
   - `mirrors`: `/etc/pacman.d/mirrorlist` and `cachyos-*mirrorlist` contain no `omarchy.org` server and at least two `Server =` lines (content hashes are not compared, because CachyOS's mirror ranking rewrites them);
   - `repo-order`: `[omarchy]` is the last repo in `pacman-conf --repo-list`;
   - `boot-packages`: `limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync` and the kernel packages report the same Packager as `baseline/packagers`;
   - `no-omarchy-kernel`: `linux-omarchy` is not installed;
   - `held-migrations`: warn (not fail) with the count from the gate log.
2. Write `package/hooks/zz-cachyos-quattro-verify.hook`: `Type=Package`, `Target=*`, `When=PostTransaction`, `Exec=/usr/lib/cachyos-quattro/verify --hook` (prints a banner on failure; PostTransaction cannot abort). Add to PKGBUILD.
3. Write `lib/cmd-status.sh`: runs `sudo /usr/lib/cachyos-quattro/verify`, then prints Omarchy version, held migrations, and an explanation that `pacman -Qkk omarchy-settings` reports the NoExtract'd files as missing by design.
4. Write `tests/unit/verify.bats` with fixture roots: all-pass for `cachyos-limine-luks`; FAIL when `omarchy_hooks.conf` is present and sorts after `mkinitcpio.conf`; FAIL when the Include line is missing; FAIL when os-release says `ID=omarchy`; FAIL when `[omarchy]` precedes `[cachyos]`; FAIL when mirrorlist is a single omarchy server line. `lsinitcpio` and `load_config` are stubbed in the fixture PATH.
5. `make check` passes.

## TDD Checklist
- [x] Write failing test
- [x] Confirm test fails (red)
- [x] Implement
- [x] Confirm test passes (green)
- [x] Confirm no regressions

## Notes
Baselines are written by `backup` (task 09). The initramfs layout differs with UKI; v1 keeps CachyOS's ENABLE_UKI value, so verify handles both the `/boot/<machine-id>/` initramfs layout and UKI files if the baseline says UKI.

As built (2026-10-21):
- Effective HOOKS follow `/usr/bin/mkinitcpio`: `mkinitcpio.conf` followed by the `mkinitcpio.conf.d/*.conf` drop-ins in `LC_ALL=C.UTF-8 sort -Vu` order (only `-c` disables drop-ins; CachyOS's Limine setup uses no presets). A unit test pins the version-sort order.
- `verify --current <hooks|limine|packagers>` prints the current value in baseline format, so `backup` (task 09) records exactly what the checks compare. Boot packages are `limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync` and the owners of `/usr/lib/modules/*/vmlinuz` (`linux-cachyos`, `linux-cachyos-lts` on the golden images).
- `--hook` prints only FAIL/warn lines and a warning, or "all 12 checks passed"; it skips all checks until `/var/lib/cachyos-quattro/installed` exists (written last by `install`, task 10). Without that, the package's own install transaction and every one before the Include is added reported failures ("error: command failed to execute correctly" in the first VM run).
- LUKS detection uses the baseline cmdline (`rd.luks.` → `sd-encrypt` + `systemd-cryptsetup` in each initramfs; `cryptdevice=` → `encrypt` + `cryptsetup`). `limine_history/` images are not inspected. With `ENABLE_UKI=yes` the initramfs check warns instead of inspecting.
- Held migrations are read from each `/home/*/.local/state/cachyos-quattro/held.log` (the gate runs per user) and counted only while the migration's marker is still absent.
- `lib/cmd-status.sh` defines `cmd_status` for the CLI (task 09 wires it into `bin/cachyos-quattro`); `tests/unit/status.bats` covers it with stubs.
- VM (`tests/vm/scenarios/verify.sh`), both golden images: all 12 checks pass on the installed state with the real `lsinitcpio` (LUKS: "2 images contain systemd-cryptsetup"), `load_config` (`ENABLE_UKI=no` on stock CachyOS) and `pacman-conf`; the hook reports after a transaction (whole transaction 2.3 s on LUKS including snap-pac); `omarchy_hooks.conf` on disk fails `noextract-absent` and `hooks`; `ID=omarchy` fails `identity`.
- Found while checking identity: CachyOS's `cachyos-branding` rewrites `/etc/os-release` on `cachyos-hooks` upgrades, so the saved copy can go stale (state.md blocker).
