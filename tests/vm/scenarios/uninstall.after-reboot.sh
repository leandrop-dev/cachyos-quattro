#!/bin/bash
# Runs on the guest after the reboot that follows uninstall.sh.

set -euo pipefail

fail() {
  echo "uninstall (after reboot): $*" >&2
  exit 1
}

backup=$(<~/cq-backup-dir)
systemctl is-system-running --wait || true
[[ $(systemctl is-enabled sddm.service || true) != enabled ]] || fail "sddm is still enabled"
[[ $(systemctl is-enabled NetworkManager-wait-online.service || true) == enabled ]] || fail "NetworkManager-wait-online.service was not restored"
grep -qx 'ID=cachyos' /etc/os-release || fail "os-release is not CachyOS"
[[ $(~/cq/package/libexec/verify --current hooks) == "$(<"$backup/baseline/hooks")" ]] || fail "HOOKS differ from the baseline"
pacman -Qq >/dev/null || fail "pacman does not run"
echo "uninstall (after reboot): ok"
