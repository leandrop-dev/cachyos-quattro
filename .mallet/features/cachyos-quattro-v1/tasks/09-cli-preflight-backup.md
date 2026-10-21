# Task: cli-preflight-backup
Status: done
Deps: 02

## Goal
Add the CLI skeleton with system detection, a refusing preflight and a backup that captures /boot, key /etc files and verification baselines.

## Steps
1. Write `bin/cachyos-quattro`: `set -euo pipefail`; resolves its repo dir; sources `lib/common.sh`; dispatches `preflight|backup|install|status|update|uninstall|recover|help` to `lib/cmd-<name>.sh`; refuses to run as root (it calls `sudo` itself).
2. Write `lib/common.sh`: `cq_log`, `cq_ok`, `cq_warn`, `cq_die`, `cq_confirm` (default no), `cq_root` path helper honouring `CQ_ROOT`, phase markers in `${CQ_ROOT}/var/lib/cachyos-quattro/phases/<name>` (`cq_phase_done`, `cq_phase_mark`).
3. Write `lib/detect.sh` with functions that print a value and never guess:
   - `cq_bootloader`: `limine` when `/boot/limine.conf` exists and `limine` is installed; `systemd-boot` when `bootctl is-installed` succeeds; `grub` when `/boot/grub/grub.cfg` exists and `grub` is installed; otherwise `unknown`. More than one match prints `multiple`.
   - `cq_root_luks`: `yes` when any ancestor of `findmnt -no SOURCE /` in `lsblk -s -no TYPE` is `crypt`, else `no`.
   - `cq_luks_style`: `systemd` when `/proc/cmdline` has `rd.luks.`, `legacy` when it has `cryptdevice=`, `none` otherwise.
   - `cq_root_fs`, `cq_snapper_configs` (`snapper --csvout list-configs`), `cq_home_separate` (`/home` is a different btrfs subvolume or mount).
   - `cq_desktop_present`: `yes` when `display-manager.service` is enabled or any of `plasma-desktop gnome-shell hyprland cachyos-hypr-noctalia greetd sddm` is installed.
   - `cq_omarchy_present`: `yes` when `omarchy` is installed or `~/.local/share/omarchy` exists.
4. Write `lib/cmd-preflight.sh`: prints every detected value, then refuses (exit 1, with the reason) unless: `/etc/os-release` has `ID=cachyos`; bootloader is `limine`; `cq_desktop_present` is `no`; `cq_omarchy_present` is `no`; on LUKS roots the effective HOOKS contain `sd-encrypt` with `systemd` style or `encrypt` with `legacy` style; root fs is btrfs with a snapper `root` config; ≥ 10 GiB free on `/`; `curl -fsI https://pkgs.omarchy.org/x86_64/omarchy.db` succeeds; `sudo -v` succeeds. `--json` is not offered.
5. Write `lib/cmd-backup.sh`, writing to `~/.local/state/cachyos-quattro/backups/<UTC timestamp>/` (on CachyOS `@home` is outside the root snapshot, so the backup survives a rollback; warn when `cq_home_separate` is `no`):
   - `sudo snapper -c root create --type single --description "cachyos-quattro pre-install" --print-number` → `snapshot.txt`;
   - `sudo tar --xattrs --acls -cpf boot.tar -C / boot` (the ESP is not covered by snapshots);
   - `etc.tar` of `/etc/pacman.conf /etc/pacman.d /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d /etc/default/limine /etc/limine-entry-tool.d /etc/os-release /etc/nsswitch.conf /etc/security/faillock.conf /etc/plymouth /etc/sysctl.d /etc/skel /etc/sddm.conf.d` (missing paths skipped and listed);
   - `home.tar` of `~/.config ~/.bashrc ~/.local/share/applications ~/.local/state/omarchy` (missing skipped);
   - `cmdline.txt`, `pacman-Qqe.txt`, `enabled-units.txt` (`systemctl list-unit-files --state=enabled --no-legend`), `manifest.tsv` (sha256 of every file written);
   - baselines to `/var/lib/cachyos-quattro/baseline/`: `hooks` (effective HOOKS), `limine` (load_config values), `packagers` (`pacman -Qi` Packager for limine, limine-mkinitcpio-hook, limine-snapper-sync, kernel packages), `cmdline`;
   - identity copies to `/var/lib/cachyos-quattro/identity/os-release` and `nsswitch.conf`.
6. Write `tests/unit/detect.bats` and `tests/unit/preflight.bats` with fixture roots and stubbed `lsblk`, `findmnt`, `bootctl`, `pacman`, `snapper`, `curl`, `sudo` on PATH: Limine+LUKS passes; GRUB refuses; desktop present refuses; LUKS with `udev encrypt` hooks and `rd.luks` cmdline refuses.
7. Write `tests/unit/backup.bats`: backup into a fixture root writes all listed files and a manifest whose hashes verify.
8. `make check` passes.

## TDD Checklist
- [x] Write failing tests
- [x] Confirm tests fail (red)
- [x] Implement
- [x] Confirm tests pass (green)
- [x] Confirm no regressions

## Notes
Fish is CachyOS's default shell; the CLI is Bash and is invoked as `./bin/cachyos-quattro`, so it does not depend on the login shell. Avoid heredocs in any instructions printed for the user to paste into fish.
- Write the baselines with `sudo /usr/lib/cachyos-quattro/verify --current hooks|limine|packagers` (task 08) instead of recomputing them, and copy `/proc/cmdline` to `baseline/cmdline`. Formats: `hooks` one line; `limine` `KEY=value` for TARGET_OS_NAME, ENABLE_UKI, BOOT_ORDER, MAX_SNAPSHOT_ENTRIES; `packagers` `<package>\t<Packager>`. Wire `lib/cmd-status.sh` (`cmd_status`) into the dispatcher.

As built (2026-10-21):
- `sudo true` instead of `sudo -v`: with sudoers' default `verifypw=all`, `-v` asks for a password unless every matching entry is NOPASSWD, so it failed on the golden images (NOPASSWD user rule plus the stock `%wheel` rule). `sudo true` prompts and caches the same way for a normal user.
- Reads under `/boot` go through `sudo test`: the golden images mount the ESP `umask=0077` (`tests/fixtures/*/etc/fstab`), so the user cannot see `/boot/limine.conf`. `findmnt -no SOURCE --nofsroot /` strips the `[/@]` subvolume suffix before `lsblk -s`.
- preflight reads effective HOOKS with the repository's `package/libexec/verify --current hooks`, because the package is not installed yet; backup writes the baselines with the same script under sudo. It reports every failed requirement, not only the first.
- backup: the manifest is `manifest.sha256` (sha256sum format, `sha256sum -c` verifies it); `missing.txt` lists skipped paths; `etc.tar` excludes `etc/pacman.d/gnupg` (pacman's local signing key does not belong in a user-readable backup); the backup directory is mode 700; `backups/latest` links to the newest; the baselines are also copied into the backup directory; backup refuses when os-release is not `ID=cachyos`.
- `bin/cachyos-quattro` dispatches to `lib/cmd-<name>.sh` and says "'<name>' is not available yet" for commands whose task has not landed. `status` is wired (task 08).
- `tests/unit/fakes.bash` is a shared fake system (sudo, pacman, findmnt, lsblk, bootctl, snapper, curl, df, systemctl, load_config) for the CLI tests.
- VM (`tests/vm/scenarios/preflight-backup.sh`), both golden images: root refused; preflight passes; backup creates snapper snapshot "cachyos-quattro pre-install", a 286 MB `boot.tar` (kernels, initramfs, limine_history), a verifying manifest and no keyring in `etc.tar`; with the guard package installed, verify passes all 12 checks against backup's baselines; status runs.
