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

## Blockers
<!-- - [ ] <description> (check off when resolved) -->
- [ ] Golden VM images need a manual CachyOS install from the ISO (Calamares) for each of Limine+LUKS and Limine plain; the user runs these once (task 03).
