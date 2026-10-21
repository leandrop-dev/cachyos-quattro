# cachyos-quattro

Install [Omarchy](https://github.com/omacom/omarchy) v4 ("Quattro") as the desktop on an
existing [CachyOS](https://cachyos.org) system, while CachyOS stays in charge of the kernel,
boot loader, initramfs, pacman mirrors and system identity. Omarchy owns the desktop;
CachyOS owns everything underneath it, across every later Omarchy release.

> **Status: tested in virtual machines only.** Every command passes on CachyOS VMs
> ([docs/testing.md](docs/testing.md)); it has not yet run on real hardware. Try it on a
> machine you can restore, and keep the backup it makes.

## Scope of v1

- CachyOS installed with **No Desktop**.
- **Limine** boot loader, with or without **LUKS** root encryption.
- Omarchy releases are followed as they ship; protections block what they do not recognise.

systemd-boot, GRUB, CachyOS desktop editions and upgrades from Omarchy v3 are planned for
later. How the protections work is recorded in
[docs/adr/0001](docs/adr/0001-protect-cachyos-with-noextract-and-gated-migrations.md).

## Install

Run everything as your normal user; the tool asks for `sudo` itself. The commands work in
fish (CachyOS's default shell) and bash.

1. Install git and clone this repository somewhere you will keep it (updates run from it):
   `sudo pacman -S --needed git` then
   `git clone https://github.com/leandrop-dev/cachyos-quattro.git ~/cachyos-quattro`
2. Check that the machine is supported. This changes nothing:
   `~/cachyos-quattro/bin/cachyos-quattro preflight`
3. Install: `~/cachyos-quattro/bin/cachyos-quattro install`

`install` runs in phases and asks before each one; a phase that finished is skipped if you run
it again, so an interrupted install resumes. It takes a snapper snapshot and a backup of
`/boot`, key `/etc` files and your home configs, installs the protections, then Omarchy, and
rebuilds the initramfs with CachyOS's tools. It says "safe to reboot" only after every check
passes. On an encrypted root, SDDM then logs you straight into Omarchy; otherwise it shows its
login screen.

## Day to day

- **Update:** `cachyos-quattro update` updates this checkout and the protections, then runs
  Omarchy's own update. `omarchy update`, the Omarchy menu's update, `pacman -Syu` and `yay`
  are safe too: the protections run inside every pacman transaction, and the checks run again
  inside Omarchy's update before it offers a reboot.
- **Check:** `cachyos-quattro status` runs every check and lists Omarchy migrations that are
  held for review.
- **Remove:** `cachyos-quattro uninstall` removes Omarchy and restores the CachyOS
  configuration from the install backup.
- **Recover:** [docs/recovery.md](docs/recovery.md) covers a failed check, booting a
  snapshot, and recovering from the CachyOS live ISO.

When an Omarchy release changes something boot-related that has not been reviewed yet, the
update stops with a message naming it, or holds the migration, until the review in this
repository lands; see [docs/reviewing-a-release.md](docs/reviewing-a-release.md).

## Blocked Omarchy commands

These rewrite the boot loader, initramfs configuration, pacman configuration, mirrors or the
root file system, so typing them prints why they are blocked and what to do instead:
`omarchy-refresh-limine`, `omarchy-refresh-pacman`, `omarchy-channel-set`,
`omarchy-upgrade-to-quattro`, `omarchy-setup-direct-boot`, `omarchy-hibernation-setup`,
`omarchy-hibernation-remove`, `omarchy-system-factory-reset`, `omarchy-reinstall-configs`,
and `omarchy-snapshot restore` (`create` works). The full list of conflicts is in
[docs/conflicts.md](docs/conflicts.md).

## Credits

This project builds on
[mroboff/omarchy-on-cachyos](https://github.com/mroboff/omarchy-on-cachyos) (Omarchy v3) and
on the findings shared by isaac30503, eloxs, Robert0X, manuelgraya and juliankgp in
[mroboff/omarchy-on-cachyos#74](https://github.com/mroboff/omarchy-on-cachyos/issues/74).

## License

[MIT](LICENSE)
