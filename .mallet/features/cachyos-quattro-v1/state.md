# State: cachyos-quattro v1

## Decisions
<!-- YYYY-MM-DD: <decision> — <reasoning> -->
- 2026-10-20: [firm] Follow upstream Omarchy releases, no version holds — user choice; protections must block unknowns instead.
- 2026-10-20: [firm] Disable Omarchy's pacman guard (mask 00-omarchy-update-guard.hook) — keep CachyOS's paru / pacman -Syu workflow.
- 2026-10-20: [firm] v1 scope: CachyOS no-desktop, Limine with and without LUKS; systemd-boot/GRUB are phase 2 (task 15); desktop editions and v3 upgrades are out of v1.
- 2026-10-20: [firm] Mechanism per ADR 0001 (NoExtract + fail-closed transaction check + early identity restore + privilege-based migration gate + stubs as UX + post-transaction verify, shipped as a pacman package) — council verdict "go with changes", all eight changes adopted.
- 2026-10-20: [firm] MIT license; predecessor (mroboff, MIT, Copyright 2025 Mark Roboff) notice kept in LICENSE if any of its code is copied.
- 2026-10-20: [firm] Plan and ADR land via branch + PR after the bootstrap commit on main.
- 2026-10-20: [firm] Bash for all runtime code; TSV ledger (no jq dependency before Omarchy is installed).
- 2026-10-20: [tentative] Omarchy keeps its Plymouth theme and plymouthd.conf, faillock.conf, cups and skel .bashrc overrides; CachyOS keeps os-release and nsswitch.conf — re-check in task 04.
- 2026-10-20: [tentative] Migration gate uses a filtered OMARCHY_PATH view rather than temporary markers; fall back to an own run loop if the view breaks migrations (task 07).
- 2026-10-21: [firm] Fixtures are built from pristine package files plus marked synthetic files, not from the development machine's boot config — that machine runs a desktop whose installer rewrites `/etc/default/limine` and adds a HOOKS-replacing mkinitcpio drop-in. Task 03 replaces the synthetic files from the golden images.
- 2026-10-21: [firm] The `btrfs-overlayfs` / `sd-btrfs-overlayfs` initcpio hooks ship in `limine-mkinitcpio-hook` 1.40.0 (`usr/lib/initcpio/install/`), not in `limine-snapper-sync` as stated in #74; task 15 corrected.
- 2026-10-21: [firm] `limine-mkinitcpio-hook` 1.40.0 itself installs `/usr/local/bin/mkinitcpio` and `/etc/pacman.d/hooks/90-mkinitcpio-install.hook`; our `/usr/local/bin` stubs must not collide with that path, and txn-check (task 06) must treat these as CachyOS-owned.
- 2026-10-21: [firm] A stock CachyOS install (ISO 260809, No Desktop) has ufw active with incoming denied; golden images add `ufw allow 22/tcp`. Task 04 must check what Omarchy's `install/config/firewall.sh` does to an already-active ufw and its existing rules.
- 2026-10-21: [firm] Stock CachyOS (ISO 260809, Limine, btrfs) boot configuration, from the golden images: HOOKS `base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth [sd-encrypt] filesystems`, plus `sd-btrfs-overlayfs` from the installer-written drop-in `/etc/mkinitcpio.conf.d/10-limine-snapper-sync.conf` (and `10-chwd-<hw>.conf` from chwd). `omarchy_hooks.conf` sorts after both, so it removes `sd-encrypt` and `sd-btrfs-overlayfs`. `/etc/default/limine` sets only `ESP_PATH`, `KERNEL_CMDLINE[default]` and `BOOT_ORDER="*, *lts, *fallback, Snapshots"`; LUKS cmdline uses `rd.luks.uuid=`; crypttab has no keyfile; snapper root keeps `NUMBER_LIMIT=50`, `NUMBER_LIMIT_IMPORTANT=15`; both `linux-cachyos` and `linux-cachyos-lts` are installed; `/etc/limine-entry-tool.d/` and `/etc/sddm.conf.d/` do not exist.
- 2026-10-21: [tentative] `TARGET_OS_NAME` is unset on stock CachyOS yet `limine.conf` shows `/+CachyOS`; the compiled `limine-entry-tool` contains both `TARGET_OS_NAME` and `/etc/os-release`, so the name is likely derived from os-release. If so, Omarchy's os-release overwrite alone breaks limine-snapper-sync. Verify in a VM in task 04 (change `NAME` in os-release, run `limine-update`, inspect `limine.conf`).
- 2026-10-21: [firm] The golden images' login shell is fish; harness SSH commands must be fish-compatible or piped to `bash -s`.

## Blockers
<!-- - [ ] <description> (check off when resolved) -->
- [ ] `main` has no server-side protection: GitHub Free blocks rulesets and branch protection on private repos (API 403). Until the repo goes public, `.claude/settings.json` deny rules and a local `.git/hooks/pre-push` guard it. When the repo is made public, add a ruleset on `main`: block deletion, block non-fast-forward pushes, require a pull request, repo owner on the bypass list.
- [x] Golden VM images need a manual CachyOS install from the ISO (Calamares) for each of Limine+LUKS and Limine plain; the user runs these once (task 03).
