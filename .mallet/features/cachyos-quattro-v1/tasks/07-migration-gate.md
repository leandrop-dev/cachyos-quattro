# Task: migration-gate
Status: done
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
- [x] Write failing test
- [x] Confirm test fails (red)
- [x] Implement
- [x] Confirm test passes (green)
- [x] Confirm no regressions

## Notes
Verified during planning: `omarchy-update` and `omarchy-migrate-notify` call `omarchy-migrate` by name (no absolute-path callers in 4.0.6), so `/usr/local/bin` precedence covers both. `omarchy-migrate` honours `OMARCHY_PATH` and `OMARCHY_MIGRATION_STATE`. If any migration breaks under the view (e.g. compares `OMARCHY_PATH` to `/usr/share/omarchy`), switch to running each allowed migration with the upstream loop body copied into the gate, and record that in state.md [tentative → firm].

As built (2026-10-21):
- The filtered OMARCHY_PATH view was dropped before writing code: migration `1786098807.sh` runs `ln -sfn "$OMARCHY_PATH/default/agents/skills/omarchy" ~/...`, which under a view would leave links into a deleted directory. The gate (`package/libexec/migrate-gate`, installed as `/usr/local/bin/omarchy-migrate`) runs allowed migrations itself with upstream's loop body and its pacman-lock wait, then upstream's notification dismiss. ADR 0001 item 4 is amended.
- `--status` (new) prints `name<TAB>verdict<TAB>reason` for each pending migration, for `cachyos-quattro status` (task 08). Held migrations are logged once per name and sha256 to `~/.local/state/cachyos-quattro/held.log` (the gate runs as the user; nothing goes to `/var/log`).
- Fail-closed details: a missing ledger runs nothing (exit 1); a `replace` verdict without our script, an unknown verdict, or a missing `$OMARCHY_PATH/bin` holds the migration.
- The view tests from step 3 became: a migration sees the real OMARCHY_PATH (symlink target check), and SIGTERM mid-run leaves the interrupted migration unmarked. The fixture migrations are synthetic rather than copies of upstream files.
- Cross-check against the real 4.0.6 tree (`build/ledger/4.0.6`, no reviews applied): the gate holds 64 and runs 56 migrations, matching `ledger/migrations.4.0.6.tsv`'s privileged column with 0 mismatches.
- `guard-package.sh` now also checks that `omarchy-migrate` resolves to the gate in the login shell and in the systemd user manager's PATH (`/usr/local/bin:/usr/bin` on the golden image), which runs `omarchy-migrate-notify`.
- Found while checking callers: `omarchy-apply-system`, `omarchy-apply-hardware`, `omarchy-provision-user` and `omarchy-provision-owner` `export PATH="$OMARCHY_PATH/bin:$PATH"`, so inside them `omarchy-migrate` and the stubbed names resolve to Omarchy's own copies. In 4.0.6 none of them calls one (matches are in comments only), and `env-bootstrap` prepends `$OMARCHY_PATH/bin` only on the dev channel. `omarchy-provision-user` marks every shipped migration done for the user. Task 12 watches for new calls.
