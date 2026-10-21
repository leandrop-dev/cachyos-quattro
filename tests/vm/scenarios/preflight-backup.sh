#!/bin/bash
# Runs on the guest. Runs `cachyos-quattro preflight` and `backup` on a stock CachyOS
# install, then installs the guard package built on the host (cd package && makepkg -f) and
# checks that verify passes against the baselines backup wrote, and that `status` runs.

set -euo pipefail

fail() {
  echo "preflight-backup: $*" >&2
  exit 1
}

cli=./bin/cachyos-quattro
lib=/var/lib/cachyos-quattro
pkg=$(find package -maxdepth 1 -name 'cachyos-quattro-*-any.pkg.tar.zst' | sort | tail -1)
[[ -n $pkg ]] || fail "no built package in package/; run 'cd package && makepkg -f' on the host"

echo "== running as root is refused"
if out=$(sudo "$cli" preflight 2>&1); then fail "the CLI ran as root"; fi
grep -q 'run as your user' <<<"$out" || fail "unexpected root refusal: $out"

echo "== preflight"
"$cli" preflight || fail "preflight refused a stock CachyOS install"

echo "== backup"
"$cli" backup || fail "backup failed"
dir=$(readlink -f ~/.local/state/cachyos-quattro/backups/latest)
(cd "$dir" && sha256sum -c --quiet manifest.sha256) || fail "manifest does not verify"
ls -l "$dir"
echo "missing (skipped): $(paste -sd ' ' "$dir/missing.txt")"
snap=$(<"$dir/snapshot.txt")
sudo snapper -c root list --columns number,description | grep -E "^ *$snap .*cachyos-quattro pre-install" ||
  fail "snapshot $snap is not in snapper's list"
sudo tar -tf "$dir/boot.tar" | grep -q 'limine.conf' || fail "boot.tar lacks limine.conf"
if sudo tar -tf "$dir/etc.tar" | grep -q gnupg; then fail "etc.tar contains pacman's keyring"; fi
for b in hooks limine packagers cmdline; do
  [[ -s $lib/baseline/$b ]] || fail "baseline $b is empty"
done
cmp /etc/os-release "$lib/identity/os-release" || fail "identity copy differs"

echo "== verify passes against backup's baselines"
sudo pacman -U --noconfirm "$pkg" >/dev/null
sudo sed -i '/^\[options\]/a Include = /etc/pacman.d/cachyos-quattro.conf' /etc/pacman.conf
repo=/var/lib/cq-fakerepo
work=$(mktemp -d)
sudo install -d -m 755 "$repo"
file=$(bash tests/vm/guest/mkfakepkg.sh "$work" cq-dummy 1.0 - usr/share/doc/cq-dummy/README)
sudo cp "$file" "$repo/"
sudo repo-add -q "$repo/omarchy.db.tar.gz" "$repo/$(basename "$file")"
printf '\n[omarchy]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$repo" | sudo tee -a /etc/pacman.conf >/dev/null
sudo touch "$lib/installed"
out=$(sudo /usr/lib/cachyos-quattro/verify) || fail "verify failed against backup's baselines: $out"
echo "$out"

echo "== status"
"$cli" status || fail "status failed"
echo "preflight-backup: ok"
