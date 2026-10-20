# Task: repo-bootstrap
Status: done
Deps: —

## Goal
Add README, MIT LICENSE and .gitignore as the first commit on main.

## Steps
1. Write `README.md`: one-paragraph purpose (Omarchy v4 desktop on CachyOS; CachyOS keeps kernel, boot loader, initramfs, mirrors, identity), a "Status: under development, do not run on a real machine" notice, v1 scope (CachyOS no-desktop, Limine with and without LUKS), a "Do not run" list (`omarchy-upgrade-to-quattro`, `omarchy-refresh-limine`, `omarchy-refresh-pacman`, `omarchy-channel-set`, `omarchy-reinstall-configs`, `omarchy-setup-direct-boot`, `omarchy-hibernation-setup`, `omarchy-system-factory-reset`), and credits to mroboff/omarchy-on-cachyos and the #74 contributors (isaac30503, eloxs, Robert0X, manuelgraya, juliankgp).
2. Write `LICENSE`: MIT, `Copyright (c) 2026 Leandro Paixão`.
3. Write `.gitignore` with: `/build/`, `/package/pkg/`, `/package/src/`, `*.pkg.tar.zst`, `/tests/vm/images/`, `/tests/vm/run/`, `*.qcow2`, `*.log`.
4. `git add README.md LICENSE .gitignore && git commit -m "Add README, license and gitignore."` on `main`.
5. `git push -u origin main` (after user confirmation).

## Notes
The plan files and ADR are not part of this commit; they go on `f/plan-cachyos-quattro` via PR.
