# Task: cli-update-uninstall-recover
Status: done
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
- [x] Write failing tests
- [x] Confirm tests fail (red)
- [x] Implement
- [x] Confirm tests pass (green)
- [x] Confirm no regressions

## Notes
Uninstall removes the desktop but cannot restore user files changed after install beyond `home.tar`; the summary says so.
- Keep the pacman.conf block removal before `pacman -Rns cachyos-quattro`: pacman refuses to start while an `Include` names a missing file (verified in task 05, including for glob patterns), so the reverse order leaves pacman stopped. The package's `pre_remove` warns about this when someone runs `pacman -R` directly.

As built (2026-10-21):
- update: `omarchy-update` ends with `omarchy-update-restart`, which offers a reboot, so a check after it can come too late. `omarchy-hook post-update` runs `~/.config/omarchy/hooks/post-update.d/*` after migrations and before that offer; install's user phase and update both write `cachyos-quattro-verify` there, so the checks also run when the update starts from the Omarchy menu (a failing hook is reported, not fatal). update rebuilds and reinstalls the guard package whenever a shipped file differs from the checkout (`cq_guard_outdated`: ledgers, libexec, hooks, stubs, the generated drop-in), not only on a pkgver change, so a ledger update always lands before Omarchy's packages. `OMARCHY_PATH` is set for `omarchy-update` (its scripts read it with `set -u`; the first VM run failed in `omarchy-update-dev` without it).
- install now writes `installed-packages.txt` in its `done` phase, so packages the system steps install are included; uninstall takes its backup from `installed` (`backup=`), not `backups/latest`, which a later manual backup would point at Omarchy's state.
- uninstall unmasks a unit that was enabled before install and is masked now: Omarchy's `enable-services.sh` masks `NetworkManager-wait-online.service`, and the first VM run could not re-enable it.
- recover restores `mkinitcpio.conf`, `mkinitcpio.conf.d`, `/etc/default/limine`, `limine-entry-tool.d`, `os-release` and `nsswitch.conf` (not every path in `etc.tar`), removes Omarchy's two drop-ins, and prints the rebuild command; the rebuild matters because `boot.tar` may hold older kernels than `/usr/lib/modules`. docs/recovery.md uses `limine-snapper-restore` (CachyOS's tool) for the snapshot route rather than `snapper rollback`.
- `cq_pacman` now makes five attempts, 15 s apart: on 2026-10-21 `mirror5.krfoss.org` (first in the golden images' CachyOS mirror lists) answered HTTP 503 for some `.sig` files and pacman did not fetch those from the next mirror; each attempt keeps what it downloaded. The install-based VM scenarios drop the `krfoss.org` mirrors (re-ranking kept them first).
- Test environment: the golden user's NOPASSWD rule does not let `sudo -v` (run by `omarchy-update-stay-awake`) pass while the stock `%wheel` rule asks for a password (`verifypw=all`); the uninstall scenario adds `Defaults:tester verifypw=any`, and docs/testing.md asks for it in future golden images. A real user has the timestamp from update's `sudo true`.
- VM `limine-luks`: recover — Omarchy's real `omarchy_hooks.conf` (from the cached package) plus a rebuild fails verify with "no systemd-cryptsetup … the LUKS root would not unlock"; recover + rebuild passes verify and the system unlocks and boots. uninstall — after install and `update -y` (the post-update hook ran inside `omarchy-update`), uninstall removes 95 explicit packages (406 with dependencies) and the guard package; pacman.conf equals the pre-install copy; HOOKS and Limine settings match the baseline; after reboot sddm is disabled and os-release is CachyOS.
- VM `limine-plain`: uninstall (after install and `update -y`) passes, including the unmask: Omarchy's `/dev/null` mask of `NetworkManager-wait-online.service` is removed and the unit is enabled after reboot; recover passes (verify fails on the broken HOOKS, passes after recover and rebuild). The `limine-luks` uninstall run predates the unmask fix.
