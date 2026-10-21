#!/bin/bash
# Runs on the guest. Installs the guard package built on the host (cd package && makepkg -f),
# serves fake Omarchy packages from a local [omarchy] repo, and checks the transaction check
# and the identity hook against real pacman transactions:
#   - a reviewed path installs, NoExtract keeps it off disk, and os-release is restored;
#   - a new boot-sensitive drop-in aborts before snap-pac takes a snapshot;
#   - CQ_TXN_ALLOW=1 passes through sudo env and pacman to the hook;
#   - pacman -U of an Omarchy package fails closed.

set -euo pipefail

fail() {
  echo "txn-check: $*" >&2
  exit 1
}

pkg=$(find package -maxdepth 1 -name 'cachyos-quattro-*-any.pkg.tar.zst' | sort | tail -1)
[[ -n $pkg ]] || fail "no built package in package/; run 'cd package && makepkg -f' on the host"
repo=/var/lib/cq-fakerepo
work=$(mktemp -d)

echo "== guard package, Include and saved identity"
sudo pacman -U --noconfirm "$pkg" >/dev/null
sudo sed -i '/^\[options\]/a Include = /etc/pacman.d/cachyos-quattro.conf' /etc/pacman.conf
sudo install -d /var/lib/cachyos-quattro/identity
sudo cp /etc/os-release /etc/nsswitch.conf /var/lib/cachyos-quattro/identity/

echo "== local [omarchy] repo, last in pacman.conf"
sudo install -d -m 755 "$repo"
printf '\n[omarchy]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$repo" | sudo tee -a /etc/pacman.conf >/dev/null
# Like omarchy-settings' .INSTALL: replace os-release on every install and upgrade.
cat >"$work/install" <<'EOF'
post_install() { rm -f /etc/os-release; printf 'NAME="Omarchy"\nID=omarchy\n' >/etc/os-release; }
post_upgrade() { post_install; }
EOF
publish() {
  local file
  file=$(bash tests/vm/guest/mkfakepkg.sh "$work" omarchy-settings "$1" "$work/install" "${@:2}")
  sudo cp "$file" "$repo/"
  sudo repo-add -q "$repo/omarchy.db.tar.gz" "$repo/$(basename "$file")"
}
snapshots() { sudo snapper --csvout list | wc -l; }

echo "== reviewed path installs"
publish 9.9.9 etc/mkinitcpio.conf.d/omarchy_hooks.conf usr/share/doc/cq-fake/README
out=$(sudo pacman -Sy --noconfirm omarchy-settings 2>&1) || fail "install of a reviewed package failed: $out"
echo "$out"
grep -q 'Checking Omarchy files against the cachyos-quattro ledger' <<<"$out" || fail "txn-check hook did not run"
[[ ! -e /etc/mkinitcpio.conf.d/omarchy_hooks.conf ]] || fail "NoExtract did not keep omarchy_hooks.conf off disk"
[[ -e /usr/share/doc/cq-fake/README ]] || fail "the package's other files were not installed"
cmp /etc/os-release /var/lib/cachyos-quattro/identity/os-release || fail "os-release was not restored"
grep -q 'restored etc/os-release' /var/log/cachyos-quattro.log || fail "restore not logged"

echo "== new drop-in aborts"
publish 9.9.10 etc/mkinitcpio.conf.d/omarchy_hooks.conf etc/mkinitcpio.conf.d/omarchy_new.conf
before=$(snapshots)
if out=$(sudo pacman -Sy --noconfirm omarchy-settings 2>&1); then
  fail "transaction with an unreviewed drop-in succeeded: $out"
fi
echo "$out"
grep -q 'unreviewed Omarchy file etc/mkinitcpio.conf.d/omarchy_new.conf (package omarchy-settings)' <<<"$out" ||
  fail "abort message missing"
[[ ! -e /etc/mkinitcpio.conf.d/omarchy_new.conf ]] || fail "omarchy_new.conf was installed"
[[ $(pacman -Q omarchy-settings) == "omarchy-settings 9.9.9-1" ]] || fail "omarchy-settings was upgraded"
[[ $(snapshots) == "$before" ]] || fail "snap-pac took a snapshot before the abort"

echo "== pacman -U of an Omarchy package fails closed"
if out=$(sudo pacman -U --noconfirm "$repo/omarchy-settings-9.9.10-1-any.pkg.tar.zst" 2>&1); then
  fail "pacman -U of an Omarchy package succeeded: $out"
fi
grep -q 'omarchy-settings is installed from a file' <<<"$out" || fail "unexpected -U output: $out"
echo "pacman -U refused"

echo "== CQ_TXN_ALLOW=1 lets it through"
out=$(sudo env CQ_TXN_ALLOW=1 pacman -S --noconfirm omarchy-settings 2>&1) || fail "CQ_TXN_ALLOW=1 did not pass: $out"
grep -q 'warning: CQ_TXN_ALLOW=1' <<<"$out" || fail "no CQ_TXN_ALLOW warning: $out"
[[ -e /etc/mkinitcpio.conf.d/omarchy_new.conf ]] || fail "omarchy_new.conf missing after CQ_TXN_ALLOW=1"
cmp /etc/os-release /var/lib/cachyos-quattro/identity/os-release || fail "os-release was not restored after upgrade"

echo "== clean up"
sudo pacman -R --noconfirm omarchy-settings >/dev/null
[[ ! -e /etc/mkinitcpio.conf.d/omarchy_new.conf ]] || fail "omarchy_new.conf left behind"
echo "txn-check: ok"
