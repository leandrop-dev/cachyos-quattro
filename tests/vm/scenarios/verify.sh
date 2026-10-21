#!/bin/bash
# Runs on the guest. Installs the guard package built on the host (cd package && makepkg -f),
# puts the system in the state `cachyos-quattro install` leaves (Include, identity copies,
# baselines written with `verify --current`, a local [omarchy] repo last), and checks that
# verify passes against the real lsinitcpio, load_config and pacman-conf, that the
# post-transaction hook reports, and that breaking a protection fails verify.

set -euo pipefail

fail() {
  echo "verify: $*" >&2
  exit 1
}

pkg=$(find package -maxdepth 1 -name 'cachyos-quattro-*-any.pkg.tar.zst' | sort | tail -1)
[[ -n $pkg ]] || fail "no built package in package/; run 'cd package && makepkg -f' on the host"
verify=/usr/lib/cachyos-quattro/verify
lib=/var/lib/cachyos-quattro
repo=/var/lib/cq-fakerepo
work=$(mktemp -d)

echo "== installed state"
out=$(sudo pacman -U --noconfirm "$pkg" 2>&1) || fail "pacman -U failed: $out"
grep -q '^error:' <<<"$out" && fail "installing the package reported errors: $out"
grep -q 'cachyos-quattro: not set up yet' <<<"$out" || fail "verify hook did not skip before install: $out"
sudo sed -i '/^\[options\]/a Include = /etc/pacman.d/cachyos-quattro.conf' /etc/pacman.conf
sudo install -d "$lib/identity" "$lib/baseline" -m 755 "$repo"
sudo cp /etc/os-release /etc/nsswitch.conf "$lib/identity/"
for b in hooks limine packagers; do
  sudo "$verify" --current "$b" | sudo tee "$lib/baseline/$b" >/dev/null
  echo "baseline $b: $(paste -sd '|' "$lib/baseline/$b")"
done
sudo cp /proc/cmdline "$lib/baseline/cmdline"
sudo touch "$lib/installed"
file=$(bash tests/vm/guest/mkfakepkg.sh "$work" cq-dummy 1.0 - usr/share/doc/cq-dummy/README)
sudo cp "$file" "$repo/"
sudo repo-add -q "$repo/omarchy.db.tar.gz" "$repo/$(basename "$file")"
printf '\n[omarchy]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$repo" | sudo tee -a /etc/pacman.conf >/dev/null
sudo pacman -Sy >/dev/null

echo "== verify passes"
out=$(sudo "$verify") || fail "verify failed on the installed state: $out"
echo "$out"

echo "== post-transaction hook"
start=$(date +%s%N)
out=$(sudo pacman -S --noconfirm cq-dummy 2>&1) || fail "transaction failed: $out"
end=$(date +%s%N)
echo "$out" | sed -n '/Running post-transaction hooks/,$p'
grep -q 'cachyos-quattro: all 12 checks passed' <<<"$out" || fail "hook did not report all checks passed"
echo "transaction with the verify hook took $(((end - start) / 1000000)) ms"

echo "== broken protections fail verify"
echo 'HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)' |
  sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf >/dev/null
if out=$(sudo "$verify"); then fail "verify passed with omarchy_hooks.conf on disk"; fi
grep -q '^FAIL noextract-absent: ' <<<"$out" || fail "noextract-absent did not fail: $out"
grep -q '^FAIL hooks: ' <<<"$out" || fail "hooks did not fail: $out"
sudo rm /etc/mkinitcpio.conf.d/omarchy_hooks.conf

sudo sed -i 's/^ID=cachyos$/ID=omarchy/' /etc/os-release
if out=$(sudo "$verify"); then fail "verify passed with ID=omarchy"; fi
grep -q '^FAIL identity: ' <<<"$out" || fail "identity did not fail: $out"
sudo cp "$lib/identity/os-release" /etc/os-release

sudo "$verify" >/dev/null || fail "verify does not pass again after the repairs"
echo "verify: ok"
