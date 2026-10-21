#!/bin/bash
# Runs on the guest. Prints the facts the conflict audit (docs/conflicts.md) relies on.
# Changes nothing.

set -uo pipefail

section() { printf '\n== %s\n' "$1"; }

section "enabled units"
for unit in NetworkManager iwd wpa_supplicant systemd-networkd systemd-resolved avahi-daemon \
  cups power-profiles-daemon ufw sshd greetd sddm; do
  printf '%-22s %s\n' "$unit" "$(systemctl is-enabled "$unit.service" 2>&1)"
done

section "NetworkManager Wi-Fi backend and DNS"
sudo grep -rhE '^\s*(wifi\.backend|dns)\s*=' /etc/NetworkManager /usr/lib/NetworkManager || echo "(no wifi.backend or dns setting; NetworkManager defaults apply)"
readlink -f /etc/resolv.conf

section "packages"
for pkg in tealdeer tldr fish paru yay neovim nvim mise zoxide starship walker quickshell iwd wpa_supplicant; do
  printf '%-14s %s\n' "$pkg" "$(pacman -Q "$pkg" 2>&1)"
done

section "tealdeer relations"
pacman -Qi tealdeer | grep -E '^(Provides|Conflicts With|Required By)'

section "login shell"
getent passwd "$USER" | cut -d: -f7
