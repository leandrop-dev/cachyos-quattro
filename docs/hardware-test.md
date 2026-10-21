# Real-hardware test

The VM release gate ([testing.md](testing.md)) proves every command on QEMU. This checklist
covers what a VM cannot: real firmware, GPUs, Wi-Fi, audio, suspend, and the keyboard at the
LUKS prompt. Run it before recommending cachyos-quattro to anyone else. Every command is a
single line, so it can be pasted into fish (CachyOS's default shell) or bash.

## Prepare

- **A machine or a disk you can wipe.** Not a daily machine: the install changes the desktop,
  and preflight refuses a system that already has one.
- **A CachyOS ISO on a USB stick**, kept for the whole test: it is also the recovery tool
  ([recovery.md](recovery.md)).
- **CachyOS installed with No Desktop, Limine, btrfs.** Ideally run the checklist twice:
  once with *Encrypt system* and once without. Set the keyboard layout you will type the
  LUKS passphrase with.
- **Note the hardware** before starting, for the report: laptop or board model, CPU, GPU
  (NVIDIA in particular), Wi-Fi chip (`lspci -k`), whether Secure Boot is on, whether another
  OS is on the disk, and where the ESP is mounted (`findmnt /boot /efi`).
- A wired network for the first run, and this page open on another device.

## Run

1. Update CachyOS and reboot once, so a CachyOS problem is not mistaken for ours:
   `sudo pacman -Syu` then `sudo reboot`
2. Get the repository. While it is private, use the GitHub CLI:
   `sudo pacman -S --needed git github-cli`, `gh auth login`, then
   `gh repo clone leandrop-dev/cachyos-quattro ~/cachyos-quattro`
3. Check the machine, and keep the output:
   `~/cachyos-quattro/bin/cachyos-quattro preflight | tee ~/cq-preflight.txt`
4. Install interactively (not `--yes`), reading what each phase says, with a log:
   `script -c "$HOME/cachyos-quattro/bin/cachyos-quattro install" ~/cq-install.log`
5. Before rebooting: `~/cachyos-quattro/bin/cachyos-quattro status | tee ~/cq-status-1.txt`
   and `sudo snapper -c root list` (expect "cachyos-quattro pre-install" and "pre-rebuild").
6. Reboot. Check the LUKS prompt accepts your passphrase with your layout, and that the
   Limine menu still shows the CachyOS entries and the Snapshots entry.

## Check after the first boot

| Area | What to check |
|---|---|
| Session | SDDM starts the Omarchy session (encrypted roots log in automatically) |
| Display | Hyprland at the native resolution; an external monitor if you have one |
| GPU | the real GPU is in use, not llvmpipe: `glxinfo -B` (package `mesa-utils`) or `vulkaninfo --summary` (`vulkan-tools`). Omarchy's own NVIDIA step is skipped on purpose; CachyOS's driver setup has to carry Hyprland |
| Shell | menus and the lock screen in colour; lock and unlock twice (from the System menu, Super + Escape, or with `omarchy-system-lock`) |
| Network | Wi-Fi from the Omarchy menu; DNS works (`resolvectl status`) |
| Audio, input | sound out, microphone, touchpad, keyboard backlight and brightness keys |
| Suspend | suspend and resume from the Omarchy menu; the lock screen comes back |
| Identity | `grep ^ID= /etc/os-release` says `cachyos`; `uname -r` is a CachyOS kernel |
| Protections | `~/cachyos-quattro/bin/cachyos-quattro status` passes every check |
| Secure Boot | if it is on: the machine still boots after the install's rebuild (not covered by the VMs) |

Hardware-specific install steps can stop the install with "needs a ledger review" on some
laptops (Intel IPU7 cameras, Dell XPS 13 speakers, Tuxedo). That is the transaction check
working; record the message, it becomes a ledger review.

## Check the day-to-day paths

1. `~/cachyos-quattro/bin/cachyos-quattro update`, then `sudo pacman -Syu`, then `yay -Syu`;
   each ends with the checks passing.
2. Reboot once more after an update that brought a new kernel.
3. Optional, on a disk you can wipe: `cachyos-quattro uninstall`, reboot, confirm CachyOS
   boots as before; then install again.

## If something breaks

Do not reboot a machine whose `status` shows a `FAIL` line. [recovery.md](recovery.md) covers
fixing it in place, booting the "cachyos-quattro pre-install" snapshot, and recovering from
the live ISO.

## Report

For each failure, keep:

- `~/cq-preflight.txt`, `~/cq-install.log`, the `status` outputs;
- `/var/log/omarchy-install.log`, `~/.local/state/cachyos-quattro/held.log`;
- `journalctl -b -p err --no-pager | tail -n 100`;
- the hardware notes from "Prepare".

Then open a GitHub issue per failure, or bring them back to a working session.
