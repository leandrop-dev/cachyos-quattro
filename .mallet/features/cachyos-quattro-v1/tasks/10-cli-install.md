# Task: cli-install
Status: pending
Deps: 03, 06, 07, 08, 09

## Goal
Implement `cachyos-quattro install`, a resumable install of Omarchy v4 that ends with a verified initramfs rebuild before any reboot.

## Steps
1. Write `lib/cmd-install.sh`; each step below is a phase guarded by `cq_phase_done`/`cq_phase_mark`, so a re-run resumes; each phase prints what it will change and asks `cq_confirm` unless `--yes`.
   1. `preflight` — run `lib/cmd-preflight.sh`; stop on failure.
   2. `backup` — run `lib/cmd-backup.sh`.
   3. `guard` — `makepkg -f` in `package/`, then `sudo pacman -U --needed package/cachyos-quattro-*.pkg.tar.zst`.
   4. `pacman-conf` — copy `/etc/pacman.conf` to the backup dir; insert directly after the `[options]` line a block `# BEGIN cachyos-quattro` / `Include = /etc/pacman.d/cachyos-quattro.conf` / `# END cachyos-quattro`; append at the end of the file `# BEGIN cachyos-quattro repo` / `[omarchy]` / `SigLevel = Required DatabaseOptional` / `Server = https://pkgs.omarchy.org/$arch` / `# END cachyos-quattro repo`, so `[omarchy]` is the last repo; confirm with `pacman-conf --repo-list | tail -1` = `omarchy` and `pacman-conf NoExtract` lists the ledger paths.
   5. `keyring` — `sudo pacman-key --recv-keys F0134EE680CAC571 && sudo pacman-key --lsign-key F0134EE680CAC571`.
   6. `packages` — `sudo pacman -Syu --needed omarchy omarchy-settings omarchy-nvim`; then `/usr/lib/cachyos-quattro/verify` must pass the `noextract-absent`, `identity`, `hooks`, `mirrors`, `repo-order` and `boot-packages` checks; stop otherwise.
   7. `base-packages` — install `/usr/share/omarchy/install/omarchy-base.packages` minus `ledger/base-packages-exclude.txt` with `sudo pacman -S --needed`; when the login shell (`getent passwd $USER`) is fish, add the packages the conflicts audit names for fish (`ledger/base-packages-shell-fish.txt`). Record `pacman -Qqe` afterwards to `installed-packages.txt` in the backup dir.
   8. `system` — for each `run` row of `ledger/install-steps.tsv`, run it as root through `install/helpers/logging.sh` `run_logged` with `OMARCHY_PATH=/usr/share/omarchy OMARCHY_INSTALL=/usr/share/omarchy/install OMARCHY_INSTALL_USER=$USER OMARCHY_LOG_TO_STDOUT=1`; stop on the first failure and print the log path.
   9. `user` — `omarchy-provision-user --force` with `OMARCHY_SETUP_CONTEXT=runtime` (never `--first-install`; `omarchy-finalize-user` does not exist in 4.0.6), prompting for `OMARCHY_USER_NAME` and `OMARCHY_USER_EMAIL`; then `cp -af /etc/skel/. ~/` (home.tar from backup is the undo), which also brings the markers for every shipped migration; create the machine-wide marker `sudo install -Dm644 /dev/null /var/lib/omarchy/migrations/1789325478` so that migration exits early even for a user without markers; then run `omarchy-migrate` (the gate), which should report nothing pending.
   10. `login` — write `/var/lib/sddm/state.conf` (`[Last]`, `Session=omarchy.desktop`, `User=$USER`, owned by `sddm:sddm`); on LUKS roots write `/etc/sddm.conf.d/autologin.conf` (`[Autologin]`, `User=$USER`, `Session=omarchy.desktop`); `sudo systemctl enable sddm.service`.
   11. `theme` — `omarchy-theme-set tokyo-night`.
   12. `rebuild` — `sudo snapper -c root create --type single --description "cachyos-quattro pre-rebuild"`; `sudo limine-mkinitcpio`; run full `verify`; on failure print the restore steps from `docs/recovery.md` and stop without suggesting a reboot.
   13. `done` — write `/var/lib/cachyos-quattro/installed` (`omarchy` version, our version, date, backup dir) and print "safe to reboot".
2. Write `tests/vm/scenarios/install.sh`: runs `./bin/cachyos-quattro install --yes` with name/email from env, asserts verify passes, reboots (the harness types the passphrase on `limine-luks`), asserts SSH is back, `systemctl is-active sddm` is `active`, `grep -q '^ID=cachyos' /etc/os-release`, and `verify` passes after reboot.
3. Run `tests/vm/run.sh limine-plain install` and `tests/vm/run.sh limine-luks install`; both pass.
4. Write `tests/unit/install-pacman-conf.bats`: the pacman.conf edit is idempotent, keeps every existing line, places the Include inside `[options]`, places `[omarchy]` last, and is fully reversed by removing the marked blocks.
5. `make check` passes.

## TDD Checklist
- [ ] Write failing test (`install-pacman-conf.bats`, VM `install` scenario)
- [ ] Confirm test fails (red)
- [ ] Implement
- [ ] Confirm test passes (green)
- [ ] Confirm no regressions

## Notes
`omarchy update` and plain `pacman -Syu` both stay safe after install: the guard hook is masked, NoExtract/txn-check/identity/verify hooks fire on every transaction, and migrations go through the gate. `--overwrite '/usr/share/omarchy/*'` in `omarchy-update-system-pkgs` does not interact with NoExtract.
