#!/bin/bash
# Runs on the guest after the reboot that follows install.sh: the system came back, SDDM
# runs, the identity is still CachyOS, and every protection check still passes.

set -euo pipefail

fail() {
  echo "install (after reboot): $*" >&2
  exit 1
}

systemctl is-system-running --wait || true
[[ $(systemctl is-active sddm.service) == active ]] || fail "sddm is not active"
grep -qx 'ID=cachyos' /etc/os-release || fail "os-release is not CachyOS"
out=$(sudo /usr/lib/cachyos-quattro/verify) || fail "verify failed after reboot: $out"
echo "$out"
loginctl list-sessions --no-legend
echo "install (after reboot): ok"
