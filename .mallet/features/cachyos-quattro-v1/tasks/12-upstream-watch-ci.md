# Task: upstream-watch-ci
Status: done
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
- [x] Write failing test
- [x] Confirm test fails (red)
- [x] Implement
- [x] Confirm test passes (green)
- [x] Confirm no regressions

## Notes
Creating issues on the GitHub repo is outward-facing; the first `workflow_dispatch` run is done with the user's confirmation.
- Also flag, in each new release: calls to `omarchy-migrate` or to a name in `package/stubbed-commands.txt` from scripts that `export PATH="$OMARCHY_PATH/bin:$PATH"` (4.0.6: `omarchy-apply-system`, `omarchy-apply-hardware`, `omarchy-provision-user`, `omarchy-provision-owner`), since there the gate and stubs are bypassed; and changes to upstream `bin/omarchy-migrate`, whose loop the gate copies.
- When checking whether a release contains an upstream fix, compare content (`git grep` of the change, or `git cherry`/patch-id), not commit ancestry: #14553 reached 4.0.x as cherry-pick `bfac6650`, and an ancestry check on `b83d3df0` wrongly reported it missing (task 16).

As built (2026-10-21):
- `tools/ledger-gen` was split: `tools/ledger-scan <tree> <outdir>` writes the ledger from an extracted tree with no network, and `ledger-gen` downloads, verifies, extracts (into `${CQ_LEDGER_WORK:-build/ledger}/<v>/`) and calls it. Regenerating 4.0.6 left every `ledger/` file unchanged.
- pkgs.omarchy.org keeps older stable packages (4.0.4 and 4.0.5 return 200), so the report compares the reviewed release's package contents with the new one's instead of git sources: `tools/upstream-diff <ledger> <reviewed-tree> <new-tree>`. It reports watched package files (boot-sensitive per the transaction check's Path targets, review status from `files.tsv`; `/etc/skel` left out as in the ledger), `.INSTALL` diffs, package relations, migrations (new ones in full; changed reviewed ones), commands (new, removed, requires-sudo changes, newly mentioning boot or pacman), diffs of `omarchy-migrate`/update commands/stubbed commands, calls that bypass the gate or stubs (command position only, a script's own name excluded), install steps and base package lists, and new repository overlap against the configured repos (Arch only in CI; CachyOS-only overlaps need a local run).
- The upstream repository is `omacom/omarchy` (`basecamp/omarchy` redirects). `tools/upstream-check` reads the stable db; `tools/upstream-early` diffs migrations between git tags for pre-releases; `tools/upstream-issue` opens one issue per title (open or closed) and cuts bodies over GitHub's 65536-character limit, linking the run, whose artifact keeps the full report.
- Real data: the 4.0.5 → 4.0.6 report is 6 KB and lists `omarchy_vconsole.conf` (reviewed noextract), migrations `1791621765.sh` (privileged: rebuilds the boot image) and `1792334754.sh`, two changed migrations, the bypass calls `omarchy-channel-set:86` → `omarchy-refresh-pacman` (dev branch only) and `omarchy-system-factory-reset:278` → `/usr/bin/omarchy-hibernation-setup`, and `hyprland-preview-share-picker` newly in both repositories. The early warning for `v4.5.0-rc1` lists 84 new migrations (45 privileged) and 4 changed, 96 KB, so it is cut.
- Tests that named 4.0.6 now read the reviewed release from `ledger/releases.tsv` (`reviewed_release` in `helpers.bash`), so a release review does not edit tests.
- `upstream-issue`'s tests were written after the tool (TDD order not followed there); the other tools' tests failed first.
- Step 6 (the first `workflow_dispatch` run) waits for the merge and the user's confirmation: it will open "Early warning: Omarchy v4.5.0-rc1" on the repository.
- The first push of the workflow was rejected by GitHub ("workflow file issue"): `run: tools/upstream-issue "Early warning: Omarchy $TAG" …` is a plain YAML scalar containing ": ". `actionlint` (installed with the user's approval) found it; `make lint` and CI now run `actionlint` on every workflow.
