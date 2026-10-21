# Task: upstream-watch-ci
Status: pending
Deps: 04

## Goal
Open a review issue automatically for every new Omarchy release, with a diff against the reviewed ledger.

## Steps
1. Write `tools/upstream-diff <old-ledger-dir> <new-build-dir>` printing Markdown sections:
   - new, removed and changed files under the boot-sensitive paths from task 06 and under `etc/`, `usr/lib/`, `usr/share/libalpm/hooks/`;
   - `.INSTALL` unified diff per package;
   - DEPENDS/CONFLICTS/PROVIDES changes;
   - new migrations (full text, `privileged` flag) and reviewed migrations whose sha256 changed;
   - changes to `bin/omarchy-migrate`, `bin/omarchy-update`, `bin/omarchy-update-system-pkgs`, `bin/omarchy-update-pacman-guard`, every stubbed command, and any `bin/omarchy-*` newly matching `limine|mkinitcpio|pacman\.conf|mirrorlist|os-release|bootctl|efibootmgr|grub`;
   - changes to scripts listed in `ledger/install-steps.tsv` and to `install/omarchy-base.packages`;
   - repo overlap changes (`omarchy.db` names that also exist in Arch/CachyOS repos — CI uses `pacman -Slq` inside an `archlinux` container with the CachyOS repos added).
2. Write `.github/workflows/upstream-watch.yml`: `schedule: cron "17 6 * * *"` plus `workflow_dispatch`; job in `archlinux:latest` container: fetch `https://pkgs.omarchy.org/x86_64/omarchy.db`, read the `omarchy` version, compare to the last row of `ledger/releases.tsv`; when newer, run `tools/ledger-gen <v> build/` and `tools/upstream-diff ledger build/` and create an issue `Review Omarchy <v>` with label `upstream-release` via `gh issue create` (skip if an open issue with that title exists). `permissions: issues: write, contents: read`.
3. Add a second job that checks `gh release list -R basecamp/omarchy --limit 5` for a pre-release newer than the reviewed version and opens `Early warning: Omarchy <tag>` with the migration diff from the git tag (source only), so review can start before the stable package ships.
4. Write `docs/reviewing-a-release.md`: how to turn the issue into ledger edits (`files.tsv`, `migrations.tsv` verdicts, `install-steps.tsv`, `base-packages-exclude.txt`), bump `releases.tsv`, bump `pkgver` in `package/PKGBUILD`, run the VM scenarios, open a PR.
5. Write `tests/unit/upstream-diff.bats` with two synthetic ledger/build trees: a new mkinitcpio drop-in, a changed reviewed migration and a new privileged migration all appear in the report.
6. Trigger the workflow with `workflow_dispatch` once and confirm it reports "no new release" against 4.0.6 (or opens the issue if 4.0.7+ exists).

## TDD Checklist
- [ ] Write failing test
- [ ] Confirm test fails (red)
- [ ] Implement
- [ ] Confirm test passes (green)
- [ ] Confirm no regressions

## Notes
Creating issues on the GitHub repo is outward-facing; the first `workflow_dispatch` run is done with the user's confirmation.
- Also flag, in each new release: calls to `omarchy-migrate` or to a name in `package/stubbed-commands.txt` from scripts that `export PATH="$OMARCHY_PATH/bin:$PATH"` (4.0.6: `omarchy-apply-system`, `omarchy-apply-hardware`, `omarchy-provision-user`, `omarchy-provision-owner`), since there the gate and stubs are bypassed; and changes to upstream `bin/omarchy-migrate`, whose loop the gate copies.
- When checking whether a release contains an upstream fix, compare content (`git grep` of the change, or `git cherry`/patch-id), not commit ancestry: #14553 reached 4.0.x as cherry-pick `bfac6650`, and an ancestry check on `b83d3df0` wrongly reported it missing (task 16).
