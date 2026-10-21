#!/bin/bash
# Runs on the guest: install, then serve a hostile "next Omarchy release" as the [omarchy]
# repository: the real cached packages repacked at pkgrel 99, where omarchy-settings now
# depends on a new package shipping an unreviewed initramfs drop-in, and omarchy ships a
# privileged migration that deletes BOOT_ORDER from /etc/default/limine.
#   - pacman -Syu must abort in the transaction check, changing nothing;
#   - the omarchy update alone (no boot-sensitive file) installs, and the migration gate holds
#     the new migration: not run, not marked, BOOT_ORDER intact.
# A test-only hook with the transaction check's mkinitcpio Path target records what pacman
# passes, to confirm task 06's assumption for NoExtract'd paths and dependency packages.

set -euo pipefail

fail() {
  echo "hostile-release: $*" >&2
  exit 1
}

bash tests/vm/guest/install-omarchy.sh || fail "install failed"

repo=/var/lib/cq-hostile
work=$(mktemp -d)
cache=/var/cache/pacman/pkg
settings=$(sudo find "$cache" -maxdepth 1 -name 'omarchy-settings-4.0.6-1-*.pkg.tar.zst' | sort | tail -n1)
omarchy=$(sudo find "$cache" -maxdepth 1 -name 'omarchy-4.0.6-1-*.pkg.tar.zst' | sort | tail -n1)
[[ -n $settings && -n $omarchy ]] || fail "the installed Omarchy packages are not in the pacman cache"

echo "== build the hostile release"
sudo install -d -m 755 "$repo"
printf 'echo "Hostile test: drop the boot order"\nsudo sed -i "/BOOT_ORDER/d" /etc/default/limine\n' >"$work/9999999999.sh"
bootfix=$(bash tests/vm/guest/mkfakepkg.sh "$work" omarchy-bootfix 1.0 - etc/mkinitcpio.conf.d/omarchy_hooks_v2.conf)
sudo cp "$bootfix" "$repo/"
sudo bash tests/vm/guest/repack.sh "$settings" "$repo" 99 depend omarchy-bootfix
sudo bash tests/vm/guest/repack.sh "$omarchy" "$repo" 99 add "$work/9999999999.sh" usr/share/omarchy/migrations/9999999999.sh
sudo repo-add -q "$repo/omarchy.db.tar.gz" "$repo"/*.pkg.tar.zst
# Point install's [omarchy] block at the hostile repository; the packages are unsigned.
sudo sed -i "/^# BEGIN cachyos-quattro repo\$/,/^# END cachyos-quattro repo\$/{s|^SigLevel = .*|SigLevel = Optional TrustAll|;s|^Server = .*|Server = file://$repo|}" /etc/pacman.conf

printf '[Trigger]\nOperation = Install\nOperation = Upgrade\nType = Path\nTarget = etc/mkinitcpio.conf.d/*\n\n[Action]\nDescription = cachyos-quattro test: record mkinitcpio path targets\nWhen = PreTransaction\nExec = /usr/bin/tee /var/tmp/cq-targets\nNeedsTargets\n' |
  sudo tee /etc/pacman.d/hooks/03-cq-debug.hook >/dev/null

echo "== pacman -Syu with the hostile release"
if out=$(sudo pacman -Syu --noconfirm 2>&1); then fail "pacman -Syu installed the hostile release: $out"; fi
echo "$out" | grep -E 'cachyos-quattro|error:'
grep -q 'unreviewed Omarchy file etc/mkinitcpio.conf.d/omarchy_hooks_v2.conf (package omarchy-bootfix)' <<<"$out" ||
  fail "the transaction check did not name the drop-in"
[[ ! -e /etc/mkinitcpio.conf.d/omarchy_hooks_v2.conf ]] || fail "the drop-in was installed"
[[ $(pacman -Q omarchy-settings) == "omarchy-settings 4.0.6-1" ]] || fail "omarchy-settings changed"
echo "Path targets pacman passed:"
cat /var/tmp/cq-targets
grep -qx 'etc/mkinitcpio.conf.d/omarchy_hooks_v2.conf' /var/tmp/cq-targets || fail "no Path target for the dependency package's file"
# pacman leaves NoExtract'd paths out of Path targets; txn-check relies on that (below).
if grep -qx 'etc/mkinitcpio.conf.d/omarchy_hooks.conf' /var/tmp/cq-targets; then
  fail "pacman passed the NoExtract'd omarchy_hooks.conf as a Path target"
fi

echo "== without the Include, the NoExtract'd file reaches the check and aborts"
sudo cp /etc/pacman.conf "$work/pacman.conf"
sudo sed -i '/^# BEGIN cachyos-quattro$/,/^# END cachyos-quattro$/d' /etc/pacman.conf
if out=$(sudo pacman -S --noconfirm omarchy-settings 2>&1); then fail "omarchy-settings installed without the Include: $out"; fi
echo "$out" | grep -E '^cachyos-quattro:'
grep -q 'etc/mkinitcpio.conf.d/omarchy_hooks.conf (package omarchy-settings) is NoExtract in the ledger, but pacman would install it' <<<"$out" ||
  fail "the transaction check did not catch the missing Include"
[[ ! -e /etc/mkinitcpio.conf.d/omarchy_hooks.conf ]] || fail "omarchy_hooks.conf was installed"
sudo cp "$work/pacman.conf" /etc/pacman.conf

echo "== the omarchy update alone"
sudo pacman -S --noconfirm omarchy || fail "the omarchy-only update failed"
[[ $(pacman -Q omarchy) == "omarchy 4.0.6-99" ]] || fail "omarchy was not updated"
out=$(OMARCHY_PATH=/usr/share/omarchy omarchy-migrate 2>&1) || fail "omarchy-migrate failed: $out"
echo "$out"
grep -q '9999999999.sh' <<<"$out" || fail "the gate did not report the hostile migration"
[[ ! -e ~/.local/state/omarchy/migrations/9999999999.sh ]] || fail "the hostile migration was marked done"
grep -q '^BOOT_ORDER=' /etc/default/limine || fail "BOOT_ORDER is gone from /etc/default/limine"
out=$(sudo /usr/lib/cachyos-quattro/verify) || fail "verify failed: $out"
grep -q '^warn held-migrations: 1 held for tester' <<<"$out" || fail "verify did not warn about the held migration: $out"

sudo rm /etc/pacman.d/hooks/03-cq-debug.hook
echo "hostile-release: ok"
