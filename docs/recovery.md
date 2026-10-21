# Recovery

What to do when an install, an update or a manual change leaves CachyOS unbootable or failing
the cachyos-quattro checks. Every command below is a single line, so it can be pasted into fish
(CachyOS's default shell) as well as bash.

## Which state is the machine in?

| Check | Meaning |
|---|---|
| `cachyos-quattro status` | runs every protection check; any `FAIL` line names what is wrong |
| `/var/lib/cachyos-quattro/installed` | exists once `cachyos-quattro install` finished; names the backup it took |
| `ls /var/lib/cachyos-quattro/phases` | the install phases that finished; `cachyos-quattro install` resumes after the last one |
| `pacman -Q cachyos-quattro omarchy` | whether the guard package and Omarchy are installed |

The backup `install` took is in `~/.local/state/cachyos-quattro/backups/<UTC time>/` (also
named in `installed`). On CachyOS `/home` is the `@home` subvolume, so the backup survives a
rollback of the root. It holds `boot.tar` (the ESP, which no snapshot covers), `etc.tar`,
`home.tar`, the baselines and `manifest.sha256` (`sha256sum -c manifest.sha256` checks it).

## The system boots, but a check fails

Do not reboot until `cachyos-quattro status` passes.

1. Read the `FAIL` lines; most name a file or a package.
2. To put the boot configuration back from the install backup on the running system:
   `cachyos-quattro recover --backup ~/.local/state/cachyos-quattro/backups/<time>`
3. Rebuild the initramfs: `sudo limine-mkinitcpio`
4. Run `cachyos-quattro status` again.

`recover` restores `/boot` from `boot.tar` and `mkinitcpio.conf`, `mkinitcpio.conf.d`,
`/etc/default/limine`, `limine-entry-tool.d`, `os-release` and `nsswitch.conf` from `etc.tar`,
and removes Omarchy's `omarchy_hooks.conf` and `limine-entry-tool.d/omarchy-*.conf`. The
rebuild afterwards matters: it writes initramfs images for the kernels installed now, which
may be newer than the ones in `boot.tar`.

## The system does not boot: use a snapshot

`install` creates two snapper snapshots: "cachyos-quattro pre-install" and "cachyos-quattro
pre-rebuild" (just before the initramfs rebuild).

1. In the Limine menu, open "Snapshots" and boot "cachyos-quattro pre-install".
2. To keep that state, run `sudo limine-snapper-restore` (from CachyOS's `limine-snapper-sync`) and follow its prompts.
3. Reboot, then run `cachyos-quattro status` or reinstall.

## The system does not boot: use the CachyOS live ISO

Boot the CachyOS ISO, open a terminal, and work as the live user (the CLI refuses to run as
root and calls `sudo` itself). Device names below are examples; `lsblk -f` shows yours.

1. Unlock the root, on encrypted installs: `sudo cryptsetup open /dev/nvme0n1p2 root`
2. Mount the root subvolume: `sudo mount -o subvol=@ /dev/mapper/root /mnt`
   (unencrypted: `sudo mount -o subvol=@ /dev/nvme0n1p2 /mnt`)
3. Mount home and the ESP: `sudo mount -o subvol=@home /dev/mapper/root /mnt/home` and `sudo mount /dev/nvme0n1p1 /mnt/boot`
4. Restore: `/mnt/home/<user>/<checkout>/bin/cachyos-quattro recover --backup /mnt/home/<user>/.local/state/cachyos-quattro/backups/<time> --target /mnt`
5. Rebuild the initramfs inside the installed system: `sudo arch-chroot /mnt limine-mkinitcpio`
6. Unmount (`sudo umount -R /mnt`) and reboot.

## Removing Omarchy

`cachyos-quattro uninstall` removes Omarchy's packages, restores the `/etc` files Omarchy
changes, re-enables the services that were enabled before install, removes the `pacman.conf`
blocks and Omarchy's key, removes the guard package, rebuilds the initramfs and compares HOOKS
and Limine settings with the pre-install baseline. It leaves Omarchy's configs in your home
(it offers to restore `home.tar`) and does not undo every change Omarchy's system setup steps
made; `/var/log/omarchy-install.log` lists them.

Do not remove the guard package with `pacman -R cachyos-quattro` on its own: pacman refuses to
start while `/etc/pacman.conf` still includes `/etc/pacman.d/cachyos-quattro.conf`. If that
happened, delete the `# BEGIN cachyos-quattro` … `# END cachyos-quattro` block from
`/etc/pacman.conf` with an editor (`sudo nano /etc/pacman.conf`).
