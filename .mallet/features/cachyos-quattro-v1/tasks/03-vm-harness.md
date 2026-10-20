# Task: vm-harness
Status: pending
Deps: 01

## Goal
Add a QEMU/OVMF harness that runs each test on a disposable overlay of a golden CachyOS image.

## Steps
1. Install host tools: `sudo pacman -S --needed edk2-ovmf openssh socat` (qemu-system-x86_64 and qemu-img are already present; /dev/kvm exists).
2. Write `docs/testing.md` § "Golden images" with the manual procedure, run once per image from the latest CachyOS ISO in a VM started by `tests/vm/install-golden.sh <name>`:
   - `limine-luks`: Calamares, "No Desktop", btrfs, Limine, encryption on, user `tester`, passphrase `cq-test-passphrase`.
   - `limine-plain`: same without encryption.
   - After first boot: `sudo pacman -S --needed openssh && sudo systemctl enable --now sshd`, add the harness public key to `~tester/.ssh/authorized_keys`, `sudo pacman -Syu`, power off.
3. Write `tests/vm/install-golden.sh <name> <iso>`: creates `tests/vm/images/<name>.qcow2` (40G), copies `/usr/share/edk2/x64/OVMF_VARS.4m.fd` to `tests/vm/images/<name>.vars.fd`, boots the ISO with `-enable-kvm -m 4096 -smp 4 -machine q35 -drive if=pflash,...OVMF_CODE.4m.fd,readonly=on -drive if=pflash,...<name>.vars.fd`, user-mode net with `hostfwd=tcp::<port>-:22`.
4. Write `tests/vm/run.sh <image> <scenario>`:
   - creates `tests/vm/run/<id>.qcow2` with `qemu-img create -f qcow2 -b ../images/<image>.qcow2 -F qcow2`, copies the VARS file;
   - boots headless with a QMP socket (`-qmp unix:tests/vm/run/<id>.qmp,server,nowait`) and serial log `tests/vm/run/<id>.serial.log`;
   - for `limine-luks`, types the passphrase through `tests/vm/qmp-type.sh` (socat + QMP `send-key`) after the serial log shows the Plymouth/cryptsetup prompt or after a fixed 20 s wait;
   - waits for SSH (timeout 180 s), copies the repo with `rsync`/`scp`, runs `tests/vm/scenarios/<scenario>.sh` over SSH, then reboots and re-checks SSH (proves the root still unlocks);
   - exits non-zero on any failure and keeps the overlay for inspection; deletes it on success unless `KEEP=1`.
5. Write `tests/vm/scenarios/smoke.sh`: asserts `grep -q '^ID=cachyos' /etc/os-release` and `systemctl is-system-running --wait` returns `running` or `degraded`.
6. Run `tests/vm/run.sh limine-luks smoke` and `tests/vm/run.sh limine-plain smoke`; both pass.
7. Replace the synthetic fixture files listed in `tests/fixtures/README.md` (`etc/default/limine`, `proc/cmdline`, the LUKS `etc/mkinitcpio.conf`) with copies from each golden image (UUIDs replaced by all-zero placeholders), update the README's source column, and run `make check`.

## TDD Checklist
- [ ] Write failing test (`smoke` scenario against a missing image fails cleanly)
- [ ] Confirm test fails (red)
- [ ] Implement run.sh and golden images
- [ ] Confirm test passes (green)
- [ ] Confirm no regressions

## Notes
Golden image creation needs the user at the VM console (Calamares is interactive). Images are never modified after creation; every run uses an overlay. If QMP passphrase timing proves flaky, fall back to watching the serial console with `console=ttyS0` added to the golden image's cmdline.
