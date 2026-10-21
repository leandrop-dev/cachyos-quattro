#!/bin/bash
# Runs on the guest: install, then break the initramfs the way an unprotected Omarchy install
# would (Omarchy's own HOOKS drop-in, taken from the cached omarchy-settings package, then a
# rebuild), then recover from the install backup and rebuild. The harness reboots; on
# limine-luks that only comes back if the recovery worked.

set -euo pipefail

fail() {
  echo "recover: $*" >&2
  exit 1
}


bash tests/vm/guest/install-omarchy.sh ||
  fail "install failed"
backup=$(sed -n 's/^backup=//p' /var/lib/cachyos-quattro/installed)

echo "== break: Omarchy's HOOKS drop-in, rebuilt"
pkg=$(sudo find /var/cache/pacman/pkg -maxdepth 1 -name 'omarchy-settings-*.pkg.tar.zst' | sort | tail -n1)
[[ -n $pkg ]] || fail "no omarchy-settings package in the pacman cache"
bsdtar -xOf "$pkg" etc/mkinitcpio.conf.d/omarchy_hooks.conf | sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf >/dev/null
sudo limine-mkinitcpio
if out=$(sudo /usr/lib/cachyos-quattro/verify); then fail "verify passed on the broken system"; fi
grep -E '^FAIL' <<<"$out"

echo "== recover"
./bin/cachyos-quattro recover --backup "$backup" || fail "recover failed"
sudo limine-mkinitcpio
out=$(sudo /usr/lib/cachyos-quattro/verify) || fail "verify still fails after recover: $out"
echo "recover: ok"
