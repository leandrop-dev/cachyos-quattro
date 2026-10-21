# Omarchy 4.0.6 on CachyOS: conflict audit

Audited 2026-10-21 against Omarchy **4.0.6** (`omarchy` and `omarchy-settings`, signed by
`40DFB630FF42BCFFB047046CF0134EE680CAC571`, "Omarchy <pkgs@omarchy.org>") and stock CachyOS
from ISO **260809** (No Desktop, btrfs, Limine, with and without LUKS; the golden images in
[testing.md](testing.md)).

The machine-readable verdicts live in `ledger/`; this page explains them. Generated inputs
(`ledger/*.4.0.6.*`) come from `tools/ledger-gen 4.0.6 ledger`.

**Ownership rule.** CachyOS owns the kernel and its command line, the boot loader, the
initramfs, pacman configuration and mirrors, system identity, and system tuning that
`cachyos-settings` sets. Omarchy owns the desktop. A package file gets `noextract` when it
changes boot, the initramfs or the command line, or overrides a value `cachyos-settings`
sets; otherwise it is installed (`ledger/files.tsv`).

## Conflicts and how each is handled

| # | Conflict | Evidence | Effect on CachyOS | Handling |
|---|---|---|---|---|
| 1 | `omarchy_hooks.conf` replaces HOOKS | `etc/mkinitcpio.conf.d/omarchy_hooks.conf` (omarchy-settings); stock HOOKS in `tests/fixtures/*/etc/mkinitcpio.conf` + `10-limine-snapper-sync.conf` | drops `systemd`, `sd-encrypt`, `sd-btrfs-overlayfs`: LUKS root cannot unlock and snapshot boot breaks after the next rebuild | noextract |
| 2 | `omarchy_vconsole.conf`, `thunderbolt_module.conf` | omarchy-settings `etc/mkinitcpio.conf.d/` | change initramfs contents | noextract |
| 3 | Limine entry-tool drop-ins | `etc/limine-entry-tool.d/omarchy-{defaults,uki}.conf` | `TARGET_OS_NAME="Omarchy"`, `ENABLE_UKI=yes`, `BOOT_ORDER` without `*lts`, `MAX_SNAPSHOT_ENTRIES=6`, cmdline additions; stock CachyOS sets none of these in `/etc/default/limine` | noextract |
| 4 | `.INSTALL` overwrites identity on every install and upgrade | `ledger/install.4.0.6.txt`: `rm -f /etc/os-release`, `cp -f` os-release, nsswitch.conf | system reports `ID=omarchy`. limine-entry-tool derives the OS entry name from os-release when `TARGET_OS_NAME` is unset (`limine-entry-tool` README, lines 347–348), which stock CachyOS leaves unset, so the next rebuild creates a new "Omarchy" tree and the Snapshots menu stops tracking | restore, in a PostTransaction hook that sorts before every initramfs hook |
| 5 | `.INSTALL` overwrites other `/etc` files | same scriptlet | Plymouth theme `cachyos-bootanimation` → `omarchy`; faillock `deny = 10`; cups and `/etc/skel/.bashrc` | allowed (desktop look and lock screen); **[tentative]**, see state.md |
| 6 | Memory tuning | `99-omarchy-sysctl.conf`, zram drop-in, zswap tmpfiles vs `cachyos-settings` `70-cachyos-settings.conf`, `zram-generator.conf`, `30-zram.rules` | overrides CachyOS values (most are identical; Omarchy adds `watermark_*`, `tcp_mtu_probing`) | noextract |
| 7 | systemd manager limits | `20-omarchy-nofile.conf` (system, user), `10-faster-shutdown.conf` vs `cachyos-settings` `10-limits.conf`, `00-timeout.conf` | lowers hard NOFILE limit 1048576 → 524288; stop timeout 10 s → 5 s | noextract |
| 8 | Omarchy's pacman guard | `usr/share/libalpm/hooks/00-omarchy-update-guard.hook` | aborts plain `pacman -Syu` and paru | masked by `/etc/pacman.d/hooks/00-omarchy-update-guard.hook` → `/dev/null` |
| 9 | Hard dependency on Limine | `ledger/packages.4.0.6.tsv`: `omarchy` depends on `limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync`, `snapper` | none on Limine installs (all four are already installed); blocks systemd-boot/GRUB | phase 2 (task 15) |
| 10 | Same packages in two repos | `ledger/repo-overlap.tsv` (27 packages) | `[omarchy]` has **higher** versions of `limine-mkinitcpio-hook` (1.40.0-2 vs 1.40.0-1) and `limine-snapper-sync` (1.32.1-2 vs 1.32.1-1) | `[omarchy]` is the last repo; verify compares Packager of boot packages |
| 11 | Migration `1789325478` | `migrations/1789325478.sh` | installs `linux-omarchy`, deletes `BOOT_ORDER` in `/etc/default/limine`, makes `linux-omarchy` first | never pending on a fresh install (`/etc/skel` marker); install also creates the machine-wide marker `/var/lib/omarchy/migrations/1789325478`, which makes it exit early |
| 12 | Migrations in later releases | `bin/omarchy-migrate` runs every unmarked migration | unknown | gate holds unreviewed privileged migrations (task 07); CI diff (task 12) |
| 13 | Install steps that write boot, initramfs or pacman config | `ledger/install-steps.tsv` | `config/snapper.sh` (retention 50/15 → 5), `hardware/nvidia.sh` (second NVIDIA driver), `post-install/pacman.sh` and `hardware/pacman.sh` (pacman.conf; the latter adds a repo with `SigLevel = Never` on T2 Macs), cmdline drop-ins (`intel/fred.sh`, two ASUS display fixes), `MODULES=(…)` overwrites (Surface, Apple SPI), `apple/fix-t2.sh` | skipped (10 of 50 scripts) |
| 14 | Commands that rewrite boot, pacman or identity | `bin/omarchy-{refresh-limine,refresh-pacman,version-channel,upgrade-to-quattro,setup-direct-boot,hibernation-setup,hibernation-remove,system-factory-reset,reinstall-configs}`, `omarchy-snapshot restore` | rewrite `limine.conf`, `pacman.conf`, mirrorlist, cmdline | `/usr/local/bin` stubs that refuse (task 05) |
| 15 | `tldr` vs `tealdeer` | golden image: `tealdeer` provides and conflicts with `tldr`, required by `cachyos-fish-config` | base package transaction aborts | `ledger/base-packages-exclude.txt` |
| 16 | **Qt 6.12 palette collision** | fix #14553 (`b83d3df0`, 2026-10-08) is not an ancestor of `v4.0.6`; its 4.0.4 backport #15265 was closed unmerged; CachyOS and Arch `extra` ship `qt6-declarative` 6.12.0 | shell surfaces lose their colours (reported by juliankgp on CachyOS) | **open** — see state.md blockers |

## Re-checked conflicts carried over from v3

| Conflict | 4.0.6 on CachyOS | Verdict |
|---|---|---|
| `tldr` vs `tealdeer` | still conflicts (#15) | exclude `tldr` |
| `wpa_supplicant` vs `iwd` | NetworkManager has no `wifi.backend` setting, so it uses wpa_supplicant; `iwd.service` and `wpa_supplicant.service` are disabled (D-Bus activation). `hardware/network.sh` disables iwd and systemd-networkd, both already disabled | no conflict |
| `walker` version pinning | `walker` 2.17.2-1 in both `[omarchy]` and `cachyos` | no conflict |
| Fish as login shell | stock CachyOS user shell is `/bin/fish`; `omarchy-fish` (Omarchy repo) sets up mise, zoxide, starship and fzf through fish `vendor_conf.d`, which loads before `cachyos-fish-config` in the user's `config.fish`. It also enables `fish_vi_key_bindings` system-wide. `omarchy-setup-fish` rewrites `~/.bashrc` and is not needed | install `omarchy-fish` (`ledger/base-packages-shell-fish.txt`); flag the vi bindings to the user |
| `yay` vs `paru` | neither is installed on a No Desktop CachyOS; `yay` 13.0.1-1 is in both repos | keep `yay` |
| CachyOS NVIDIA driver | `hardware/nvidia.sh` installs `nvidia-open-dkms` and early-KMS `MODULES`; the `nvidia-580xx-*` overlap comes from CachyOS by repo order | skip `nvidia.sh` |
| `nvim` unresolvable | on CachyOS `pacman -Sp nvim` resolves to `cachyos-extra-v3/neovim` | no exclusion needed |
| `quickshell-git` vs `quickshell` | no longer in the 4.0.6 base list; migration `1787399318` moved Omarchy back to packaged `quickshell` | no conflict |

## Other CachyOS facts the plan relies on

- ufw is active on stock CachyOS with incoming denied; Omarchy's `config/firewall.sh` keeps
  existing rules and sets the same default.
- NetworkManager uses `dns=systemd-resolved` (`cachyos-settings`); Omarchy's
  `enable-services.sh` enables `systemd-resolved`, which is already enabled.
- `power-profiles-daemon` is installed but disabled on CachyOS; Omarchy enables it.
- `/etc/limine-entry-tool.d/` and `/etc/sddm.conf.d/` do not exist on stock CachyOS.
- `omarchy-provision-user` is the user setup command in 4.0.6; `omarchy-finalize-user`,
  named in Omarchy's own `docs/file-layout.md`, does not exist.
- `/etc/skel/.local/state/omarchy/migrations/` ships a marker for each of the 120 migrations,
  so none of them runs for a user created from, or seeded with, `/etc/skel`.
