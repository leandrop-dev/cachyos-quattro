# Task: cli-update-uninstall-recover
Status: pending
Deps: 10

## Goal
Add `update`, `uninstall` and `recover` commands and the recovery guide.

## Steps
1. Write `lib/cmd-update.sh`:
   - `git -C <repo> pull --ff-only` when the repo is a git checkout, then rebuild and `pacman -U` our package when its pkgver changed (new ledger first, so the gate and txn-check know the new release);
   - run `verify`; stop on failure;
   - run `omarchy-update` (it calls `omarchy-migrate` → the gate);
   - run `verify` again; print held migrations and the review-issue URL pattern `https://github.com/leandrop-dev/cachyos-quattro/issues?q=label:upstream-release`.
2. Write `lib/cmd-uninstall.sh` (confirms twice; every step logged):
   - `sudo systemctl disable sddm.service`; re-enable units present in the backup's `enabled-units.txt` and absent now; disable units enabled since (diff of current enabled list vs backup);
   - remove packages in `installed-packages.txt` minus `pacman-Qqe.txt` with `sudo pacman -Rns`, including `omarchy omarchy-settings omarchy-keyring omarchy-nvim`;
   - restore from `etc.tar`: `/etc/os-release`, `/etc/nsswitch.conf`, `/etc/security/faillock.conf`, `/etc/plymouth/plymouthd.conf`, `/etc/skel/.bashrc`, `/etc/sddm.conf.d`; remove `/var/lib/sddm/state.conf` if the install wrote it;
   - remove both `# BEGIN/END cachyos-quattro` blocks from `/etc/pacman.conf`; `sudo pacman-key --delete F0134EE680CAC571`;
   - `sudo pacman -Rns cachyos-quattro`;
   - offer `tar -xpf home.tar -C ~` (default no);
   - `sudo limine-mkinitcpio`, then compare effective HOOKS and limine values to the baseline;
   - print a summary of what was restored and what was left (e.g. user files created after install).
3. Write `lib/cmd-recover.sh --backup <dir> [--target <mountpoint>]` for use from the CachyOS live ISO: restores `/boot` from `boot.tar` and the `/etc` files from `etc.tar` into `<mountpoint>` (default `/`), removes `<mountpoint>/etc/mkinitcpio.conf.d/omarchy_hooks.conf` and `<mountpoint>/etc/limine-entry-tool.d/omarchy-*.conf` if present, and prints the `arch-chroot <mountpoint> limine-mkinitcpio` command to run next.
4. Write `docs/recovery.md`:
   - boot a Limine "Snapshots" entry for the pre-install snapshot, then `snapper rollback`;
   - from the CachyOS ISO: `cryptsetup open /dev/<part> root`, `mount -o subvol=@ /dev/mapper/root /mnt`, mount `@home` and the ESP at `/mnt/boot`, run `/mnt/home/<user>/<repo>/bin/cachyos-quattro recover --backup /mnt/home/<user>/.local/state/cachyos-quattro/backups/<ts> --target /mnt`, `arch-chroot /mnt limine-mkinitcpio`;
   - how to tell which state the machine is in (`cachyos-quattro status`, `/var/lib/cachyos-quattro/installed`, `pacman -Q cachyos-quattro omarchy`).
5. Write `tests/vm/scenarios/uninstall.sh`: after `install`, run `uninstall --yes`, reboot, assert `pacman -Q omarchy` fails, `/etc/pacman.conf` equals the backup copy, effective HOOKS equal the baseline, SSH comes back (LUKS unlocks).
6. Write `tests/vm/scenarios/recover.sh`: after `install`, overwrite `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` with the upstream file and rebuild with `CQ_TXN_ALLOW=1` to simulate breakage; run `recover --backup <dir>` then `limine-mkinitcpio`; reboot; assert SSH comes back.
7. Write `tests/unit/uninstall.bats` for the pacman.conf block removal and unit-list diff logic against fixtures.
8. Run the VM scenarios on both images; `make check` passes.

## TDD Checklist
- [ ] Write failing tests
- [ ] Confirm tests fail (red)
- [ ] Implement
- [ ] Confirm tests pass (green)
- [ ] Confirm no regressions

## Notes
Uninstall removes the desktop but cannot restore user files changed after install beyond `home.tar`; the summary says so.
- Keep the pacman.conf block removal before `pacman -Rns cachyos-quattro`: pacman refuses to start while an `Include` names a missing file (verified in task 05, including for glob patterns), so the reverse order leaves pacman stopped. The package's `pre_remove` warns about this when someone runs `pacman -R` directly.
