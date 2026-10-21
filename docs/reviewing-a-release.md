# Reviewing an Omarchy release

cachyos-quattro follows Omarchy releases without version holds, and its protections block what
the ledger has not reviewed. So a new Omarchy release that touches a reviewed area stops at a
protection on users' machines until it is reviewed here. This page turns the review issue
into ledger edits.

## Where the work comes from

The `Upstream watch` workflow (`.github/workflows/upstream-watch.yml`) runs every day:

- **Review Omarchy &lt;version&gt;**: Omarchy's stable repository has a release newer than the
  last `reviewed` row of `ledger/releases.tsv`. The body is `tools/upstream-diff`'s report;
  the full report is the run's `review-report` artifact when the body was cut.
- **Early warning: Omarchy &lt;tag&gt;**: a GitHub pre-release newer than the reviewed release.
  The body lists the migrations it adds or changes, from the source. Start reviewing those
  early; the package review comes with the stable release.

Both are labelled `upstream-release`; `cachyos-quattro update` prints that label's issue list
when migrations are held.

To produce the same report locally:

```bash
CQ_LEDGER_WORK=$PWD/build/watch tools/ledger-gen <reviewed> build/watch/gen-reviewed
CQ_LEDGER_WORK=$PWD/build/watch tools/ledger-gen <new> build/watch/gen-new
tools/upstream-diff ledger build/watch/<reviewed> build/watch/<new>
```

## What each section asks for

| Report section | What the protection does until it is reviewed | Ledger change |
|---|---|---|
| Package files outside the desktop payload | a new or renamed file under a boot-sensitive path aborts the transaction (`txn-check`) | a row in `ledger/files.tsv`: `noextract` when it changes boot, the initramfs, the kernel command line, or a value `cachyos-settings` sets; `allow` otherwise. Update `docs/conflicts.md` |
| `.INSTALL` | nothing: it runs as root on every install and upgrade | when it writes a new `/etc` file, decide between allowing it, restoring it (`package/libexec/restore-identity`) and listing it in uninstall (`CQ_UNINSTALL_ETC` in `lib/cmd-uninstall.sh`) |
| Package relations | nothing | a new dependency that conflicts with CachyOS goes to `ledger/base-packages-exclude.txt` or needs a decision in `state.md` |
| Migrations | the gate holds an unreviewed privileged migration, and a reviewed one whose sha256 changed, without marking it | a row in `ledger/migrations.tsv` keyed by name and sha256: `run`, `skip` (marked without running) or `replace` (with `package/migrations/<name>`). Migrations a fresh install never runs because `/etc/skel` ships their marker can be `preseed`, but existing installs still run them, so review privileged ones |
| Commands | none for new commands | a new command that rewrites boot, pacman or identity gets a stub: `package/stubbed-commands.txt` and a case in `package/libexec/stub` |
| `omarchy-migrate` and stubbed commands | the gate copies upstream's loop; the stubs refuse | port loop changes to `package/libexec/migrate-gate`; recheck each stub's message |
| Calls that bypass the gate or the stubs | none: these calls run Omarchy's own commands | decide whether the call path is reachable on CachyOS; record it in `docs/conflicts.md` |
| Install steps | `cachyos-quattro install` refuses to start with an unreviewed step | a row in `ledger/install-steps.tsv`: `run` or `skip` with the reason |
| `omarchy-base.packages` | a new conflict makes the base-packages transaction fail | `ledger/base-packages-exclude.txt`, or the fish list |
| Packages newly in both repositories | repository order decides; `[omarchy]` is last | rows in `ledger/repo-overlap.tsv`; for boot packages, the verify check compares the Packager |

When checking whether a release contains an upstream fix, compare content (`git grep`, or
`git cherry`), not commit ancestry: fixes reach the 4.0.x line as cherry-picks.

## Finishing the review

1. Regenerate the generated ledger for the new release and drop the old one:
   `tools/ledger-gen <new> ledger`, then `git rm ledger/*.<reviewed>.*`.
2. Add `<new>	<date>	reviewed` to `ledger/releases.tsv`. The unit tests read the reviewed
   release from there.
3. Bump `pkgrel` (or `pkgver` for code changes) in `package/PKGBUILD`.
4. Run `make check`, then the VM scenarios on both golden images
   (`tests/vm/run.sh limine-luks install`, `uninstall`, `recover`, and the same for
   `limine-plain`); record the results in `docs/testing.md`.
5. Open a PR that closes the review issue. After it merges, `cachyos-quattro update` on a
   machine pulls the checkout, reinstalls the guard package with the new ledger, and only
   then runs Omarchy's update.
