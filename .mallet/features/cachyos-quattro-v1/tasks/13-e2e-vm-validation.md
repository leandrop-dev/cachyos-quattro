# Task: e2e-vm-validation
Status: pending
Deps: 03, 11, 16

## Goal
Prove every protection and command end to end on the Limine-LUKS and Limine-plain golden images and record the results.

## Steps
1. Write `tests/vm/scenarios/hostile-release.sh`: after `install`, build a local repo (`repo-add`) with a fake `omarchy-settings` at a higher pkgver that adds `etc/mkinitcpio.conf.d/omarchy_hooks_v2.conf` (udev/encrypt HOOKS) and a fake `omarchy` that adds migration `9999999999.sh` running `sudo sed -i '/BOOT_ORDER/d' /etc/default/limine`; place the repo before `[omarchy]` in a test-only pacman.conf block; run `sudo pacman -Syu`; assert the transaction aborts with the txn-check message; allow it with `CQ_TXN_ALLOW=1` only for an `omarchy`-only update without the drop-in, run `omarchy-migrate`, assert `9999999999.sh` is held (no marker, BOOT_ORDER intact).
2. Write `tests/vm/scenarios/plain-pacman.sh`: after `install`, run `sudo pacman -Syu --noconfirm` and `paru -Syu --noconfirm` (if paru is installed on the image); assert the Omarchy guard does not block and `verify` passes.
3. Write `tests/vm/scenarios/shell-ui.sh`: after `install`, start the Omarchy session, check the Qt 6.12 palette (state.md blocker) by screenshotting a menu through QMP `screendump` and comparing against a reference, and lock and unlock twice (quickshell 0.3.2 lock report).
4. Write `tests/vm/scenarios/menu-commands.sh`: after `install`, run each stubbed command and assert exit 1 with its message; run `omarchy-plymouth-set-by-theme tokyo-night` (allowed) and assert `verify` passes afterwards (initramfs rebuilt with CachyOS HOOKS).
5. Write `tests/vm/scenarios/kernel-update.sh`: after `install`, reinstall `linux-cachyos` (`sudo pacman -S --noconfirm linux-cachyos`), reboot, assert SSH returns and `verify` passes.
6. Run every scenario (`smoke install plain-pacman shell-ui menu-commands kernel-update hostile-release uninstall recover`) on `limine-luks` and `limine-plain`.
7. Record in `docs/testing.md` § "Results": date, Omarchy version, CachyOS ISO date, image, scenario, pass/fail, and any issue links. Each failure becomes a GitHub issue or a fix PR before this task is marked done.
8. Confirm the `Type = Path` hook behaviour assumed in task 06 (fires for NoExtract'd paths and for dependency packages) and record the finding in state.md.

## TDD Checklist
- [ ] Write failing test (each scenario runs red before its protection is in place, e.g. on a golden image without the guard package)
- [ ] Confirm test fails (red)
- [ ] Implement fixes found by the runs
- [ ] Confirm test passes (green)
- [ ] Confirm no regressions

## Notes
Nothing in this task touches a real machine. The real-hardware run (Limine ± LUKS) happens only after all scenarios pass, with the user present, and is not part of this task.
- Shell screendumps work on the harness's default `-vga std`: Hyprland and `quickshell -p /usr/share/omarchy/shell` run there (task 16). From SSH, load the session environment first (`. /usr/share/omarchy/default/bash/env-bootstrap; export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1)`), then `omarchy-menu summon` and `omarchy-system-lock`; capture with QMP `{"execute":"screendump","arguments":{"filename":"<f>.png","format":"png"}}` (QEMU 11.1). The LUKS image autologins, so the session is up after unlock.
