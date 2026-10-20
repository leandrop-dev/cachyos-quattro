# cachyos-quattro

Install [Omarchy](https://github.com/basecamp/omarchy) v4 ("Quattro") as the desktop on an
existing [CachyOS](https://cachyos.org) system, while CachyOS stays in charge of the kernel,
boot loader, initramfs, pacman mirrors and system identity. Omarchy owns the desktop;
CachyOS owns everything underneath it, across every later Omarchy release.

> **Status: under development. Do not run this on a real machine yet.**
> Nothing here has been released or tested on hardware.

## Scope of v1

- CachyOS installed with **No Desktop**.
- **Limine** boot loader, with or without **LUKS** root encryption.
- Omarchy releases are followed as they ship; protections block what they do not recognise.

systemd-boot, GRUB, CachyOS desktop editions and upgrades from Omarchy v3 are planned for
later. How the protections work is recorded in
[docs/adr/0001](docs/adr/0001-protect-cachyos-with-noextract-and-gated-migrations.md).

## Do not run on CachyOS

These Omarchy commands rewrite the boot loader, initramfs configuration, pacman
configuration or mirrors:

- `omarchy-upgrade-to-quattro`
- `omarchy-refresh-limine`
- `omarchy-refresh-pacman`
- `omarchy-channel-set` / `omarchy channel set`
- `omarchy-reinstall-configs`
- `omarchy-setup-direct-boot`
- `omarchy-hibernation-setup`
- `omarchy-system-factory-reset`

## Credits

This project builds on
[mroboff/omarchy-on-cachyos](https://github.com/mroboff/omarchy-on-cachyos) (Omarchy v3) and
on the findings shared by isaac30503, eloxs, Robert0X, manuelgraya and juliankgp in
[mroboff/omarchy-on-cachyos#74](https://github.com/mroboff/omarchy-on-cachyos/issues/74).

## License

[MIT](LICENSE)
