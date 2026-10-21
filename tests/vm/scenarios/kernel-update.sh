#!/bin/bash
# Runs on the guest: after install, reinstall the kernel, which rebuilds the initramfs and the
# boot entries through CachyOS's hooks; every check must pass before and after the reboot.

set -euo pipefail

fail() {
  echo "kernel-update: $*" >&2
  exit 1
}

bash tests/vm/guest/install-omarchy.sh || fail "install failed"
out=$(sudo pacman -S --noconfirm linux-cachyos 2>&1) || fail "reinstalling linux-cachyos failed: $out"
grep -E 'cachyos-quattro|Checking CachyOS protections' <<<"$out" || true
grep -q 'cachyos-quattro: all 12 checks passed' <<<"$out" || fail "the verify hook did not pass after the kernel transaction: $out"
echo "kernel-update: ok"
