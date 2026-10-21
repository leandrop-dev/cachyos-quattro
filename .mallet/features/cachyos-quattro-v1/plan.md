# Feature: cachyos-quattro v1
Status: planning
Created: 2026-10-20
Branch: —

## Goal
Install Omarchy v4 on an existing CachyOS system and keep CachyOS in charge of the kernel, boot loader, initramfs, pacman mirrors, identity and memory tuning across every later Omarchy release.

## Context
Omarchy v4 ships as the pacman packages `omarchy` and `omarchy-settings` (pkgs.omarchy.org, key F0134EE680CAC571); the v3 predecessor's sed-on-install.sh approach no longer applies. The protection mechanism is fixed by [ADR 0001](../../../docs/adr/0001-protect-cachyos-with-noextract-and-gated-migrations.md): exact-path NoExtract, a fail-closed transaction file check, an early identity-restore hook, a privilege-based migration gate backed by a SHA-256-pinned ledger, explanatory stubs, post-transaction verification, all shipped as a local pacman package plus a Bash CLI, with CI diffing every upstream release. v1 scope: CachyOS with no desktop, Limine with and without LUKS, following upstream releases without holds, Omarchy's pacman guard disabled.

## Repository layout (decided)
```
bin/cachyos-quattro            CLI entry point (dispatches to lib/cmd-*.sh)
lib/                           common.sh, detect.sh, ledger.sh, cmd-*.sh
package/                       PKGBUILD for the cachyos-quattro pacman package
package/hooks/                 ALPM hooks
package/libexec/               scripts the hooks and stubs run
package/stubs/                 /usr/local/bin stubs (incl. omarchy-migrate gate)
package/pacman.d/              cachyos-quattro.conf (NoExtract drop-in)
ledger/                        files.tsv, migrations.tsv, packages.tsv, releases.tsv
tools/                         ledger-gen, upstream-diff (dev/CI only)
tests/unit/                    bats tests; tests/fixtures/ fake roots
tests/vm/                      QEMU/OVMF harness and golden-image procedure
docs/                          adr/, conflicts.md, recovery.md, testing.md
```
Every runtime script honours `CQ_ROOT` (default empty) as a path prefix so unit tests run against fixture roots.

## Tasks
- [x] 01-repo-bootstrap — README, LICENSE (MIT), .gitignore as the first commit on main [deps: —] [parallel: no]
- [x] 02-unit-test-harness — bats + shellcheck via Makefile and a CI workflow [deps: 01] [parallel: yes]
- [x] 03-vm-harness — QEMU/OVMF golden images (Limine ± LUKS) and a disposable-overlay test runner [deps: 01] [parallel: yes]
- [x] 04-conflict-audit-and-ledger — ledger generator, 4.0.6 baseline ledger and docs/conflicts.md [deps: 01] [parallel: yes]
- [ ] 05-guard-package — PKGBUILD with NoExtract drop-in, guard-hook mask, identity restore hook and stubs [deps: 02, 04] [parallel: no]
- [ ] 06-transaction-check — fail-closed PreTransaction check for unreviewed boot-sensitive files [deps: 05] [parallel: no]
- [ ] 07-migration-gate — omarchy-migrate wrapper that holds unreviewed privileged migrations [deps: 05] [parallel: no]
- [ ] 08-verify-and-status — post-transaction verification hook and `cachyos-quattro status` [deps: 05] [parallel: no]
- [ ] 09-cli-preflight-backup — CLI skeleton, system detection, preflight and backup [deps: 02] [parallel: yes]
- [ ] 10-cli-install — end-to-end install flow [deps: 03, 06, 07, 08, 09] [parallel: no]
- [ ] 11-cli-update-uninstall-recover — update wrapper, uninstall and recovery docs [deps: 10] [parallel: no]
- [ ] 12-upstream-watch-ci — scheduled job diffing new Omarchy releases against the ledger [deps: 04] [parallel: yes]
- [ ] 13-e2e-vm-validation — run every scenario on both golden images and record results [deps: 03, 11] [parallel: no]
- [ ] 14-upstream-foreign-base-proposal — draft an upstream opt-out proposal for user review [deps: 13] [parallel: no]
- [ ] 15-other-bootloaders — systemd-boot and GRUB support (phase 2) [deps: 13] [parallel: no]

## Supporting Skills
None.
