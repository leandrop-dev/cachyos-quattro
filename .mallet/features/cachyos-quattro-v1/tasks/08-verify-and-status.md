# Task: verify-and-status
Status: pending
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
- [ ] Write failing test
- [ ] Confirm test fails (red)
- [ ] Implement
- [ ] Confirm test passes (green)
- [ ] Confirm no regressions

## Notes
Baselines are written by `backup` (task 09). The initramfs layout differs with UKI; v1 keeps CachyOS's ENABLE_UKI value, so verify handles both the `/boot/<machine-id>/` initramfs layout and UKI files if the baseline says UKI.
