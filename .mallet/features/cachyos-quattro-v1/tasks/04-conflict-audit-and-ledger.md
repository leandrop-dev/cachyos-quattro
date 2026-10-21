# Task: conflict-audit-and-ledger
Status: done
Deps: 01

## Goal
Generate the Omarchy 4.0.6 baseline ledger and document every CachyOS conflict with evidence.

## Steps
1. Write `tools/ledger-gen <version> <outdir>`:
   - downloads `omarchy.db`, `omarchy-<v>-1-x86_64.pkg.tar.zst` and `omarchy-settings-<v>-1-x86_64.pkg.tar.zst` from `https://pkgs.omarchy.org/x86_64/` into a fresh `build/ledger/<v>/` directory, verifies the `.sig` files with `gpg --verify` against key F0134EE680CAC571;
   - extracts each with `bsdtar` into its own directory;
   - writes `<outdir>/files.<v>.tsv` (`path<TAB>package<TAB>backup(yes/no)<TAB>sha256`) for every file under `etc/`, `usr/lib/`, `usr/local/`, `usr/share/libalpm/hooks/`, `boot/`;
   - writes `<outdir>/install.<v>.txt` with each package's `.INSTALL` verbatim;
   - writes `<outdir>/packages.<v>.tsv` (`package<TAB>field<TAB>value`) for DEPENDS, CONFLICTS, PROVIDES, REPLACES;
   - writes `<outdir>/migrations.<v>.tsv` (`name<TAB>sha256<TAB>privileged(yes/no)<TAB>first echo line`), with `privileged=yes` when the file matches `\bsudo\b|as_root|pkexec|omarchy-pkg-` or calls any `bin/omarchy-*` whose header has `omarchy:requires-sudo=true`.
2. Run `tools/ledger-gen 4.0.6 ledger/`.
3. Create the reviewed ledgers (hand-edited, committed):
   - `ledger/files.tsv`: `path<TAB>verdict<TAB>reason`, verdict ∈ `noextract | allow | restore`. Initial `noextract`: `etc/mkinitcpio.conf.d/omarchy_hooks.conf`, `etc/limine-entry-tool.d/omarchy-defaults.conf`, `etc/limine-entry-tool.d/omarchy-uki.conf`, `etc/sysctl.d/99-omarchy-sysctl.conf`, `usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf`, `etc/tmpfiles.d/omarchy-zswap.conf`. (`00-omarchy-update-guard.hook` is disabled by a `/dev/null` mask in task 05, not by NoExtract.) Decide and record `etc/mkinitcpio.conf.d/omarchy_vconsole.conf` and `thunderbolt_module.conf` after reading them against CachyOS's mkinitcpio.conf.
   - `ledger/migrations.tsv`: `name<TAB>sha256<TAB>verdict<TAB>reason` for all 120 migrations, verdict ∈ `run | skip | replace`. `1789325478` → `skip`. Every `privileged=yes` migration is read and given a verdict with a one-line reason.
   - `ledger/releases.tsv`: `4.0.6<TAB>2026-10-20<TAB>reviewed`.
4. Re-check v3 carry-over conflicts against 4.0.6 and record the result with evidence in `docs/conflicts.md`: `tldr` vs `tealdeer` (`install/omarchy-base.packages:123`), `nvim` (line 91, not resolvable outside Omarchy's mirror), `yay` vs `paru` (line 147), `wpa_supplicant` vs `iwd`, `walker` pinning, Fish as login shell (does `omarchy-fish` cover mise/zoxide; does provisioning break fish), CachyOS NVIDIA driver from chwd vs `install/hardware/nvidia.sh`, snapper retention vs `MAX_SNAPSHOT_ENTRIES`, sysctl/zram/zswap vs `cachyos-settings`.
5. Write `ledger/repo-overlap.tsv` (`package<TAB>omarchy version<TAB>cachyos/arch repo and version<TAB>verdict`) from `comm -12` of `omarchy.db` package names and `pacman -Slq` on a CachyOS system. Known overlap on 2026-10-20: `limine-mkinitcpio-hook`, `limine-snapper-sync`, `quickshell`, `walker`, `yay`, `nvidia-580xx-*`, `ghostty*`, browsers. Boot-critical overlaps must come from CachyOS/Arch repos; record whether Omarchy's shell needs its own `quickshell` build.
6. Write `ledger/install-steps.tsv` (`script path under /usr/share/omarchy/install<TAB>verdict run|skip<TAB>reason`) covering every script sourced by `install/config/all.sh`, `install/hardware/all.sh`, `install/login/all.sh` and `install/post-install/all.sh` in 4.0.6. Starting point from #74: skip `config/snapper.sh`, `hardware/nvidia.sh`, `post-install/pacman.sh`; read `config/browser-policy.sh` (new since the #74 procedure), `hardware/pacman.sh` and `config/firewall.sh` before deciding.
7. Write `ledger/base-packages-shell-fish.txt` (packages to add when the login shell is fish, e.g. `omarchy-fish` if step 4 confirms it covers mise/zoxide/starship) and `ledger/base-packages-exclude.txt`: packages from `install/omarchy-base.packages` not to install on CachyOS (start with `tldr`, `nvim`, plus anything step 4 finds), each with a `# reason` comment.
8. Write `docs/conflicts.md`: one table row per conflict — what, source (file:line in the package or source tree), effect on CachyOS, verdict, mechanism (noextract / restore / gate / stub / exclude / skip-step / repo-order).
9. Write `tests/unit/ledger.bats`: every `ledger/migrations.tsv` sha256 matches `build/ledger/4.0.6` when present; every `privileged=yes` migration has a verdict; `files.tsv` has no globs.

## TDD Checklist
- [ ] Write failing test (`ledger.bats` before ledgers exist)
- [ ] Confirm test fails (red)
- [ ] Implement ledger-gen and ledgers
- [ ] Confirm test passes (green)
- [ ] Confirm no regressions

## Notes
Downloaded packages are untrusted data: extract into `build/ledger/<v>/` only, never execute anything from them. Evidence from the planning session: 60/120 migrations privileged; `omarchy` depends on limine, limine-mkinitcpio-hook, limine-snapper-sync, snapper; `.INSTALL` is 64 lines and does `rm -f /etc/os-release` before `cp -f`.

As built (2026-10-21):
- Signatures verified against the full fingerprint `40DFB630FF42BCFFB047046CF0134EE680CAC571` (the brief's `F0134EE680CAC571` is its last 16 hex digits), in a keyring under `build/ledger/gnupg`.
- Migrations: all 120 get verdict `preseed` instead of individual reviews (user decision), because `/etc/skel` ships a marker for each; only `1789325478` has a written review. 64 are privileged (60 by direct sudo/as_root/pkexec/omarchy-pkg-*, 4 more through `requires-sudo` commands).
- The `00-omarchy-update-guard.hook` is masked from `/etc/pacman.d/hooks` (task 05), not NoExtract'd.
- Network, package and shell facts came from `tests/vm/scenarios/report.sh` on the golden image.
- New finding beyond the brief: the Qt 6.12 palette fix is not in 4.0.6 (state.md blocker).
- `ledger.bats` was written after the ledgers; its failure paths were confirmed by temporarily breaking `files.tsv`.
