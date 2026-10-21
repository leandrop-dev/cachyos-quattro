#!/bin/bash
# Runs on the guest after the reboot that follows kernel-update.sh.

set -euo pipefail

fail() {
  echo "kernel-update (after reboot): $*" >&2
  exit 1
}

out=$(sudo /usr/lib/cachyos-quattro/verify) || fail "verify failed after reboot: $out"
installed=$(pacman -Ql linux-cachyos | sed -n 's|^linux-cachyos /usr/lib/modules/\([^/]*\)/vmlinuz$|\1|p')
[[ $(uname -r) == "$installed" ]] || fail "running kernel $(uname -r), installed $installed"
echo "kernel-update (after reboot): ok"
