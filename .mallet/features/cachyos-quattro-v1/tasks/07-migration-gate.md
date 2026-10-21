# Task: migration-gate
Status: pending
Deps: 05

## Goal
Shadow omarchy-migrate with a gate that runs reviewed migrations by verdict and holds unreviewed privileged ones without ever marking them done.

## Steps
1. Write `package/stubs/omarchy-migrate` (installed to `/usr/local/bin/omarchy-migrate`):
   - loads `/usr/share/cachyos-quattro/ledger/migrations.tsv`;
   - for each `/usr/share/omarchy/migrations/*.sh` without a marker in `${OMARCHY_MIGRATION_STATE:-$HOME/.local/state/omarchy/migrations}`, classifies it: ledger hit with matching sha256 → its verdict (`run`, `skip`, `replace`; `preseed` is treated as no entry); ledger name hit with a different sha256 → `held` (changed upstream); no ledger entry → `held` if it matches `\bsudo\b|as_root|pkexec|omarchy-pkg-` or calls an `omarchy-*` helper whose header contains `omarchy:requires-sudo=true`, otherwise `run`;
   - builds a view in `$XDG_RUNTIME_DIR/cachyos-quattro/view-$$/`: a symlink for every entry of `/usr/share/omarchy` except `migrations/`, and a `migrations/` directory with symlinks to `run` migrations, `replace` migrations pointing at `/usr/share/cachyos-quattro/migrations/<name>`, `skip` migrations omitted (the gate writes their marker itself, since skip is a reviewed decision), `held` migrations omitted (no marker);
   - runs `OMARCHY_PATH=<view> /usr/bin/omarchy-migrate "$@"`; removes the view on exit via `trap`;
   - `--pending` prints only non-held pending migrations, then held ones prefixed `held:` on stderr, and keeps upstream exit codes (0 when any non-held pending, 1 otherwise);
   - appends each held migration to `/var/log/cachyos-quattro.log` (via the user-writable `~/.local/state/cachyos-quattro/held.log` when not root) and sends one `notify-send` summary when a session bus exists.
2. Write `package/migrations/` (initially empty, with a `README` stating that each file is a reviewed replacement named exactly like the upstream migration) and add it to the PKGBUILD.
3. Write `tests/unit/gate.bats` with a fixture `usr/share/omarchy/migrations/` and a fake `/usr/bin/omarchy-migrate` (copy of upstream 4.0.6 `bin/omarchy-migrate`):
   - reviewed `run` migration runs and is marked;
   - reviewed `skip` is marked and does not run;
   - `replace` runs our script, not upstream's;
   - unreviewed `sudo sed -i … /etc/default/limine` migration (copy of `1789325478`) is held: not run, no marker, logged;
   - unreviewed unprivileged migration runs;
   - reviewed name with changed sha256 is held;
   - killing the gate mid-run (`timeout -s INT`) leaves no marker for held migrations and no view directory;
   - a migration using `$OMARCHY_PATH/default/...` resolves through the view.
4. `make check` passes; `makepkg -f` builds.

## TDD Checklist
- [ ] Write failing test
- [ ] Confirm test fails (red)
- [ ] Implement
- [ ] Confirm test passes (green)
- [ ] Confirm no regressions

## Notes
Verified during planning: `omarchy-update` and `omarchy-migrate-notify` call `omarchy-migrate` by name (no absolute-path callers in 4.0.6), so `/usr/local/bin` precedence covers both. `omarchy-migrate` honours `OMARCHY_PATH` and `OMARCHY_MIGRATION_STATE`. If any migration breaks under the view (e.g. compares `OMARCHY_PATH` to `/usr/share/omarchy`), switch to running each allowed migration with the upstream loop body copied into the gate, and record that in state.md [tentative → firm].
