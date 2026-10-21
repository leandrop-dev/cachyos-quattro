# Feature: cachyos-quattro v1
Status: done (v1 MVP, 2026-10-21); phase 2 in the roadmap below
Created: 2026-10-20
Branch: one f/<task> branch and PR per task (PRs #1–#17)

## Goal
Install Omarchy v4 on an existing CachyOS system and keep CachyOS in charge of the kernel, boot loader, initramfs, pacman mirrors, identity and memory tuning across every later Omarchy release.

## Context
Omarchy v4 ships as the pacman packages `omarchy` and `omarchy-settings` (pkgs.omarchy.org, key F0134EE680CAC571); the v3 predecessor's sed-on-install.sh approach no longer applies. The protection mechanism is fixed by [ADR 0001](../../../docs/adr/0001-protect-cachyos-with-noextract-and-gated-migrations.md): exact-path NoExtract, a fail-closed transaction file check, an early identity-restore hook, a privilege-based migration gate backed by a SHA-256-pinned ledger, explanatory stubs, post-transaction verification, all shipped as a local pacman package plus a Bash CLI, with CI diffing every upstream release. v1 scope: CachyOS with no desktop, Limine with and without LUKS, following upstream releases without holds, Omarchy's pacman guard disabled.

## Repository layout (decided)
```
bin/cachyos-quattro            CLI entry point (dispatches to lib/cmd-*.sh)
lib/                           common.sh, detect.sh, pacman-conf.sh, cmd-*.sh
package/                       PKGBUILD for the cachyos-quattro pacman package, stubbed-commands.txt
package/hooks/                 ALPM hooks (04 txn-check, 05 identity, zz verify)
package/libexec/               txn-check, restore-identity, migrate-gate, stub, verify
package/migrations/            reviewed replacement migrations
ledger/                        reviewed verdicts and the generated *.<release>.* files
tools/                         ledger-gen, ledger-scan, gen-noextract, upstream-* (dev/CI only)
tests/unit/                    bats tests; tests/fixtures/ fake roots
tests/vm/                      QEMU/OVMF harness, golden-image procedure, scenarios
docs/                          adr/, conflicts.md, recovery.md, testing.md, reviewing-a-release.md, hardware-test.md
```
Every runtime script honours `CQ_ROOT` (default empty) as a path prefix so unit tests run against fixture roots.

## Tasks
- [x] 01-repo-bootstrap — README, LICENSE (MIT), .gitignore as the first commit on main [deps: —] [parallel: no]
- [x] 02-unit-test-harness — bats + shellcheck via Makefile and a CI workflow [deps: 01] [parallel: yes]
- [x] 03-vm-harness — QEMU/OVMF golden images (Limine ± LUKS) and a disposable-overlay test runner [deps: 01] [parallel: yes]
- [x] 04-conflict-audit-and-ledger — ledger generator, 4.0.6 baseline ledger and docs/conflicts.md [deps: 01] [parallel: yes]
- [x] 05-guard-package — PKGBUILD with NoExtract drop-in, guard-hook mask, identity restore hook and stubs [deps: 02, 04] [parallel: no]
- [x] 06-transaction-check — fail-closed PreTransaction check for unreviewed boot-sensitive files [deps: 05] [parallel: no]
- [x] 07-migration-gate — omarchy-migrate wrapper that holds unreviewed privileged migrations [deps: 05] [parallel: no]
- [x] 08-verify-and-status — post-transaction verification hook and `cachyos-quattro status` [deps: 05] [parallel: no]
- [x] 09-cli-preflight-backup — CLI skeleton, system detection, preflight and backup [deps: 02] [parallel: yes]
- [x] 10-cli-install — end-to-end install flow [deps: 03, 06, 07, 08, 09] [parallel: no]
- [x] 11-cli-update-uninstall-recover — update wrapper, uninstall and recovery docs [deps: 10] [parallel: no]
- [x] 12-upstream-watch-ci — scheduled job diffing new Omarchy releases against the ledger [deps: 04] [parallel: yes]
- [x] 13-e2e-vm-validation — run every scenario on both golden images and record results [deps: 03, 11, 16] [parallel: no]
- [x] 16-qt612-bridge — closed without code: Omarchy 4.0.6 renders correctly on Qt 6.12.0 (verified in the VM) [deps: 10] [parallel: no]

## Next for v1
- [ ] Real-hardware run with the user present, following docs/hardware-test.md: the step before recommending v1 to others.

## Roadmap (phase 2)
Not part of v1. Each item becomes a task when picked up.
- [ ] 14-upstream-foreign-base-proposal — draft an upstream opt-out proposal for user review (task file kept).
- [ ] 15-other-bootloaders — systemd-boot and GRUB support (task file kept).
- [ ] Keep the saved identity current: refresh `/var/lib/cachyos-quattro/identity/os-release` when CachyOS's `cachyos-branding` rewrites `/etc/os-release` (state.md).
- [ ] Make the repository public, then add the `main` ruleset (state.md).
- [ ] Review Omarchy 4.5 when it ships stable (issue #16: 84 new migrations, 45 privileged).

## Supporting Skills
None.
