#!/bin/bash
# Runs on the guest. A full `cachyos-quattro install --yes` from the internet on a stock
# CachyOS install, then every protection check before the harness reboots.

set -euo pipefail

fail() {
  echo "install: $*" >&2
  exit 1
}

start=$(date +%s)
# mirror5.krfoss.org and mirror.krfoss.org head the golden images' CachyOS mirror lists and
# answered HTTP 503 for some .sig files on 2026-10-21, failing whole transactions; re-ranking
# kept them first. Drop them so these scenarios test cachyos-quattro, not one mirror.
sudo sed -i '/krfoss\.org/d' /etc/pacman.d/cachyos-mirrorlist /etc/pacman.d/cachyos-v3-mirrorlist /etc/pacman.d/cachyos-v4-mirrorlist

CQ_USER_NAME="CQ Tester" CQ_USER_EMAIL="tester@example.invalid" ./bin/cachyos-quattro install --yes ||
  fail "install failed"
echo "install took $((($(date +%s) - start) / 60)) min"

out=$(sudo /usr/lib/cachyos-quattro/verify) || fail "verify failed after install: $out"
echo "$out"
grep -qx 'ID=cachyos' /etc/os-release || fail "os-release is not CachyOS"
pacman -Q omarchy omarchy-settings cachyos-quattro
[[ -e /var/lib/cachyos-quattro/installed ]] || fail "install did not record itself"
cat /var/lib/cachyos-quattro/installed
echo "install: ok"
