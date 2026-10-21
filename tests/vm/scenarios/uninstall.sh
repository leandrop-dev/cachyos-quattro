#!/bin/bash
# Runs on the guest: install, update (nothing new to fetch is fine), then uninstall --yes.
# The harness reboots and uninstall.after-reboot.sh checks the system is CachyOS again.

set -euo pipefail

fail() {
  echo "uninstall: $*" >&2
  exit 1
}

# mirror5.krfoss.org and mirror.krfoss.org head the golden images' CachyOS mirror lists and
# answered HTTP 503 for some .sig files on 2026-10-21, failing whole transactions; re-ranking
# kept them first. Drop them so these scenarios test cachyos-quattro, not one mirror.
sudo sed -i '/krfoss\.org/d' /etc/pacman.d/cachyos-mirrorlist /etc/pacman.d/cachyos-v3-mirrorlist /etc/pacman.d/cachyos-v4-mirrorlist

CQ_USER_NAME="CQ Tester" CQ_USER_EMAIL="tester@example.invalid" ./bin/cachyos-quattro install --yes ||
  fail "install failed"
backup=$(sed -n 's/^backup=//p' /var/lib/cachyos-quattro/installed)
echo "$backup" >~/cq-backup-dir

echo "== update"
# omarchy-update-stay-awake runs `sudo -v`, which asks for a password unless every sudoers rule
# matching the user is NOPASSWD (verifypw=all) and the stock %wheel rule is not. A real user has
# the timestamp `sudo true` cached at the start of update; the NOPASSWD test user never does.
echo "Defaults:tester verifypw=any" | sudo tee /etc/sudoers.d/11-tester-verifypw >/dev/null
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
