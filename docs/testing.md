# Testing

Two layers, and neither touches a real machine:

- **Unit tests** — `make check` runs shellcheck and the bats tests in `tests/unit/` against
  fake roots in `tests/fixtures/`. CI runs the same target on every push and pull request.
- **VM tests** — `tests/vm/run.sh <image> <scenario>` boots a disposable copy of a CachyOS
  install under QEMU/KVM with UEFI (OVMF), runs a scenario over SSH, reboots, and checks
  that the machine comes back. On LUKS images the harness types the passphrase, so a
  passing run proves the root still unlocks.

## Host requirements

`qemu-desktop` (or `qemu-full`), `edk2-ovmf`, `openssh`, `socat`, and `/dev/kvm`. Plan for
40 GiB of disk per golden image plus a few GiB per kept run.

## Golden images

A golden image is a CachyOS install made once, by hand, and then sealed read-only. Every
test run boots a copy-on-write overlay of it, so the image itself never changes.
Calamares is interactive, so creating an image needs someone at the VM window.

Images, the ISO and the harness SSH key live in `tests/vm/images/`, which git ignores.

| Image | Installer choices |
|---|---|
| `limine-luks` | Boot loader **Limine**, file system **btrfs**, **Encrypt system** on, passphrase `cq-test-passphrase` |
| `limine-plain` | Boot loader **Limine**, file system **btrfs**, no encryption |

### 1. Get the ISO

Download `cachyos-desktop-linux-<date>.iso` and its `.sha256` from
`https://mirror.cachyos.org/ISO/desktop/<date>/` into `tests/vm/images/`, then check it:

```bash
cd tests/vm/images && sha256sum -c cachyos-desktop-linux-<date>.iso.sha256
```

### 2. Install

```bash
tests/vm/golden.sh install limine-luks tests/vm/images/cachyos-desktop-linux-<date>.iso
```

A QEMU window opens on the live ISO. Run the installer with:

- **Keyboard:** English (US). The harness types the LUKS passphrase as US key codes.
- **Partitions:** Erase disk, btrfs, and for `limine-luks` tick *Encrypt system* with the
  passphrase `cq-test-passphrase`.
- **Boot loader:** Limine.
- **Desktop:** No Desktop.
- **User:** name `tester`, any password, with administrator rights.

When the installer finishes, power the VM off, not reboot, so it doesn't boot the ISO again.

### 3. Prepare

```bash
tests/vm/golden.sh boot limine-luks
```

Log in on the VM console as `tester` (for `limine-luks`, enter the passphrase first) and run:

```bash
sudo pacman -Syu --needed openssh
sudo systemctl enable --now sshd
sudo ufw allow 22/tcp
echo 'tester ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/10-tester
```

CachyOS enables ufw with incoming connections denied, so SSH needs the explicit rule.

From the host, in the repository root, install the harness key (it asks for the
`tester` password once). `ssh-copy-id` needs `~/.ssh` to exist on the host:

```bash
mkdir -p -m 700 ~/.ssh
ssh-copy-id -i tests/vm/images/id_ed25519 -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null tester@127.0.0.1
```

Every golden image answers on `127.0.0.1:2222` with its own host key, so the command keeps
them out of `~/.ssh/known_hosts`. If an earlier run saved one there, remove it with
`ssh-keygen -R '[127.0.0.1]:2222'`.

Power the VM off from its console: `sudo systemctl poweroff`.

### 4. Seal

```bash
tests/vm/golden.sh seal limine-luks
```

This makes the disk and its UEFI variables read-only and writes the checksum to
`tests/vm/images/limine-luks.info`. Repeat steps 2–4 for `limine-plain`.

The SSH server, the ufw rule for port 22 and the passwordless sudo rule exist only so
scenarios can run unattended. They are the only changes made to an otherwise stock install.

## Running scenarios

```bash
tests/vm/run.sh limine-luks smoke
tests/vm/run.sh limine-plain smoke
```

Each run:

1. creates an overlay in `tests/vm/run/`;
2. boots it headless and types the passphrase on `*-luks*` images;
3. copies the working tree to `~/cq` on the guest;
4. runs `tests/vm/scenarios/<scenario>.sh`;
5. reboots;
6. runs `<scenario>.after-reboot.sh`, or `smoke.sh` if there isn't one.

A failing run keeps its overlay and serial log in `tests/vm/run/`; `KEEP=1` keeps them
on success too.

## Results

| Date | Omarchy | CachyOS ISO | Image | Scenario | Result |
|---|---|---|---|---|---|
| 2026-10-21 | none (guard package 0.1.0-1 only) | 260809 | limine-plain | guard-package | pass |
| 2026-10-21 | none (fake omarchy-settings from a local repo) | 260809 | limine-plain | txn-check | pass |
| 2026-10-21 | none (guard package with migration gate) | 260809 | limine-plain | guard-package | pass |
| 2026-10-21 | none (guard package with verify hook) | 260809 | limine-luks | verify | pass |
| 2026-10-21 | none (guard package with verify hook) | 260809 | limine-plain | verify | pass |
