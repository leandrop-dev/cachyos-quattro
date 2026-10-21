#!/bin/bash
# Runs on the guest: install, update (nothing new to fetch is fine), then uninstall --yes.
# The harness reboots and uninstall.after-reboot.sh checks the system is CachyOS again.

set -euo pipefail

fail() {
  echo "uninstall: $*" >&2
  exit 1
}


bash tests/vm/guest/install-omarchy.sh ||
  fail "install failed"
backup=$(sed -n 's/^backup=//p' /var/lib/cachyos-quattro/installed)
echo "$backup" >~/cq-backup-dir

echo "== update"
./bin/cachyos-quattro update -y || fail "update failed"
[[ -f ~/.config/omarchy/hooks/post-update.d/cachyos-quattro-verify ]] || fail "post-update hook missing"

echo "== uninstall"
./bin/cachyos-quattro uninstall --yes || fail "uninstall failed"
if pacman -Qq omarchy >/dev/null; then fail "omarchy is still installed"; fi
if pacman -Qq cachyos-quattro >/dev/null; then fail "cachyos-quattro is still installed"; fi
cmp /etc/pacman.conf "$backup/pacman.conf.before-install" || fail "pacman.conf differs from before install"
grep -qx 'ID=cachyos' /etc/os-release || fail "os-release is not CachyOS"
[[ ! -e /etc/sddm.conf.d ]] || fail "/etc/sddm.conf.d is still there"
echo "uninstall: ok"
