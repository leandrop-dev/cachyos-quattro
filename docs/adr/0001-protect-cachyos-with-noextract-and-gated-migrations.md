# 0001. Protect CachyOS with NoExtract, transaction checks and gated migrations

Date: 2026-10-20
Status: Accepted

## Context

cachyos-quattro installs Omarchy v4 ("Quattro", github.com/basecamp/omarchy) on an
existing CachyOS system. CachyOS keeps the kernel, boot loader, initramfs, pacman
mirrors, system identity and memory tuning; Omarchy owns the desktop.

Omarchy v4 ships as the pacman packages `omarchy` and `omarchy-settings` from
`https://pkgs.omarchy.org/$arch`. Its updates run `pacman -Syu`, then
`omarchy-migrate` (per user, once per migration, marked under
`~/.local/state/omarchy/migrations/`). Upstream moves fast: 4.0.4 on 2026-09-15,
4.0.5 and 4.0.6 on 2026-10-18/19, v4.5.0-rc1 on 2026-10-20. We follow upstream
releases without version holds, and Omarchy's pacman guard is disabled so plain
`pacman -Syu` and paru keep working.

What crosses the line between base and desktop, from the 4.0.6 packages:

- Files extracted by `omarchy-settings`: `etc/mkinitcpio.conf.d/omarchy_hooks.conf`
  (replaces the whole HOOKS array with udev/encrypt, dropping sd-encrypt and
  sd-btrfs-overlayfs, so an encrypted root using `rd.luks.uuid=` cannot unlock
  after the next rebuild), `etc/limine-entry-tool.d/omarchy-{defaults,uki}.conf`
  (TARGET_OS_NAME, ENABLE_UKI, BOOT_ORDER without LTS, MAX_SNAPSHOT_ENTRIES=6,
  cmdline additions), `etc/sysctl.d/99-omarchy-sysctl.conf`, a zram-generator
  drop-in and a tmpfiles rule disabling zswap.
- The `omarchy-settings` `.INSTALL` scriptlet: on every install and upgrade it runs
  `rm -f /etc/os-release` and `cp -f` copies from `/usr/share/omarchy/etc-overrides/`
  over os-release, nsswitch.conf, faillock.conf, plymouthd.conf, cups files and
  `/etc/skel/.bashrc`.
- Migrations: 60 of the 120 migrations in 4.0.6 run privileged work (`sudo`,
  `as_root`, `omarchy-pkg-*`). Migration `1789325478` uses `sudo sed` on
  `/etc/default/limine` to delete BOOT_ORDER, installs `linux-omarchy`, and runs
  `sudo limine-mkinitcpio` — without calling any `omarchy-*` command.
- User-reachable commands that rewrite boot, pacman or identity
  (`omarchy-refresh-limine`, `omarchy-refresh-pacman`, `omarchy-upgrade-to-quattro`,
  `omarchy-setup-direct-boot`, `omarchy-hibernation-setup`, …). Some Omarchy
  commands call others by absolute path (`omarchy-refresh-sddm` execs
  `$OMARCHY_PATH/bin/omarchy-plymouth-set`, which runs `limine-mkinitcpio`).

The community workarounds in mroboff/omarchy-on-cachyos#74 and
juliankgp/omarchy-cachyos use late-sorting override files and a keyword grep that
permanently marks matching migrations as done. The decision was tested with a
four-advisor council before acceptance.

## Decision

We will block rejected Omarchy files at extraction time, check every transaction
for unreviewed files in boot-sensitive paths, restore overwritten identity files
after each transaction, and gate privileged migrations against a reviewed,
SHA-256-pinned ledger — all shipped as a locally built pacman package plus a Bash
CLI, with scheduled CI that diffs each new Omarchy release against the ledger.

Concretely:

1. `NoExtract` with exact paths only, in a drop-in our package owns
   (`/etc/pacman.d/cachyos-quattro.conf`), pulled into `[options]` by one
   `Include` line in `/etc/pacman.conf`. The `etc-overrides` source files are
   never blocked, because `.INSTALL` deletes `/etc/os-release` before copying.
2. A PreTransaction path-triggered hook that aborts when a transaction would
   install an unreviewed file under `etc/mkinitcpio.conf.d/`,
   `etc/limine-entry-tool.d/`, `etc/default/limine`, `etc/pacman.*`,
   `etc/sysctl.d/`, `etc/tmpfiles.d/`, the zram-generator drop-in directories,
   or `boot/`.
3. A PostTransaction hook that restores CachyOS's `/etc/os-release` and
   `/etc/nsswitch.conf`, named to sort before every initramfs hook (`05-…`).
4. An `omarchy-migrate` wrapper (the gate). Reviewed migrations follow their
   ledger verdict (run, skip, or replace). Unreviewed migrations that use
   `sudo`, `as_root`, `pkexec`, `omarchy-pkg-*`, or a helper marked
   `omarchy:requires-sudo=true` are held: never run and never marked. The real
   `omarchy-migrate` runs against a filtered view, so no temporary markers exist
   to be orphaned. Unreviewed unprivileged migrations run.
5. `/usr/local/bin` stubs for commands that rewrite boot, pacman or identity
   configuration. They explain and refuse; they are user experience, not the
   protection boundary. Plymouth theme commands stay allowed, because an
   initramfs rebuild uses CachyOS's own HOOKS once `omarchy_hooks.conf` is blocked.
6. A PostTransaction verification: effective mkinitcpio HOOKS, `lsinitcpio`
   contents (sd-encrypt on LUKS roots), effective limine-entry-tool values,
   os-release identity, pacman.conf and mirrorlist checksums.
7. A machine-readable per-release ledger (files, `.INSTALL` lines, migrations by
   name and SHA-256, verdicts) as the repo's primary data artifact, feeding the
   NoExtract list, the transaction check, the gate, CI and docs.

## Alternatives Considered

- **A. Override files and repair hooks** (the #74 approach) — late-sorting
  drop-ins freeze a copy of today's HOOKS, which goes stale when CachyOS changes
  its own configuration, and they depend on file sort order. Overrides in
  `/etc/default/limine` are deleted by migration `1789325478`. The keyword
  migration filter lets unknown migrations through and permanently marks
  harmless ones as done.
- **C. Repackage `omarchy-settings` / `omarchy`** — removes the conflicts at the
  source but means rebuilding and re-auditing every upstream release (four point
  releases in five weeks), which one maintainer cannot sustain. Kept as the
  fallback if NoExtract proves to break Omarchy.
- **D. Manual procedure plus checker** — no lasting protection; every update is a
  manual risk. Becomes viable only if upstream adds a "foreign base" opt-out.
- **Loose files copied by a script** instead of a pacman package — no ownership
  record, no clean uninstall, and `pacman -Qkk` cannot tell our files apart.

## Consequences

- **Strongest objection (council): the protections let unknown changes through.**
  A keyword gate misses privileged migrations that use helpers, and exact-path
  NoExtract misses a renamed or newly added drop-in, which on LUKS means an
  unbootable root at the next kernel update. Answer: the gate holds by privilege,
  not keywords, and the transaction check aborts on any unreviewed file in
  boot-sensitive paths. Both block what they don't recognise.
- Following upstream with blocking checks means an Omarchy update can be held
  or aborted until the ledger is updated. The CI diff job exists to keep that
  wait short; the maintainer must review each release promptly.
- `pacman -Qkk omarchy-settings` reports NoExtract'd files as missing; `status`
  must explain that.
- Merging a `pacman.conf.pacnew` with pacdiff can drop the `Include` line; the
  post-transaction verification must catch it.
- Our package installs files under `/usr/local/bin` and `/etc/pacman.d/`, which
  Arch packaging normally avoids; this is deliberate so the stubs precede
  `/usr/bin` in `PATH` and sudo's `secure_path`.
- The `[omarchy]` repo also carries builds of `limine-mkinitcpio-hook`,
  `limine-snapper-sync`, `quickshell`, `walker`, `yay` and `nvidia-580xx-*`.
  pacman takes a package from the first repo that lists it, so `[omarchy]` is
  placed after every CachyOS and Arch repo, and verification checks that
  boot-critical packages still come from CachyOS.
- Held migrations leave Omarchy features missing until reviewed.
- If a VM test shows that NoExtract makes `omarchy` or its migrations fail hard,
  we move to C (repackaging). If upstream accepts a foreign-base opt-out, most of
  this layer can be retired in favour of D plus a checker.
- Follow-on work: VM test harness (Limine with and without LUKS), the 4.0.6
  ledger baseline, CI diff job, and later support for systemd-boot and GRUB
  (stub package for omarchy's hard dependency on `limine`,
  `limine-mkinitcpio-hook`, `limine-snapper-sync` and `snapper`).
