#!/bin/bash
# Runs on the guest: after install, CachyOS's own update paths keep working: plain
# `pacman -Syu` and the AUR helper Omarchy installs (yay; No Desktop CachyOS ships no paru) are
# not stopped by Omarchy's update guard, and every check passes afterwards.

set -euo pipefail

fail() {
  echo "plain-pacman: $*" >&2
  exit 1
}

bash tests/vm/guest/install-omarchy.sh || fail "install failed"

echo "== pacman -Syu"
out=$(sudo pacman -Syu --noconfirm 2>&1) || fail "pacman -Syu failed: $out"
grep -q 'Omarchy updates should normally run' <<<"$out" && fail "Omarchy's update guard stopped pacman"
grep -E 'cachyos-quattro|there is nothing to do' <<<"$out" || true

echo "== yay -Syu"
command -v yay >/dev/null || fail "yay is not installed"
out=$(yay -Syu --noconfirm 2>&1) || fail "yay -Syu failed: $out"
grep -q 'Omarchy updates should normally run' <<<"$out" && fail "Omarchy's update guard stopped yay"

out=$(sudo /usr/lib/cachyos-quattro/verify) || fail "verify failed: $out"
echo "plain-pacman: ok"
