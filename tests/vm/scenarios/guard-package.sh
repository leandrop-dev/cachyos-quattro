#!/bin/bash
# Runs on the guest. Installs the guard package built on the host (cd package && makepkg -f),
# with no Omarchy present, and checks what pacman and the shell make of it: the hooks
# parse, the scriptlet reports the missing Include, the Include activates every NoExtract
# entry, the stubs win on PATH and under sudo, and removing the package while the Include
# remains stops pacman.

set -euo pipefail

fail() {
  echo "guard-package: $*" >&2
  exit 1
}

pkg=$(find package -maxdepth 1 -name 'cachyos-quattro-*-any.pkg.tar.zst' | sort | tail -1)
[[ -n $pkg ]] || fail "no built package in package/; run 'cd package && makepkg -f' on the host"
dropin=/etc/pacman.d/cachyos-quattro.conf
include="Include = $dropin"

echo "== install without the Include"
out=$(sudo pacman -U --noconfirm "$pkg" 2>&1) || fail "pacman -U failed: $out"
echo "$out"
grep -q '^error:' <<<"$out" && fail "pacman reported errors"
grep -q "does not read $dropin yet" <<<"$out" || fail "scriptlet did not report the missing Include"

echo "== Include in [options]"
sudo sed -i "/^\[options\]/a $include" /etc/pacman.conf
expected=$(sed -n 's/^NoExtract = //p' "$dropin")
[[ $(pacman-conf NoExtract) == "$expected" ]] || fail "pacman-conf NoExtract does not match $dropin"
echo "pacman-conf lists $(grep -c . <<<"$expected") NoExtract entries"
out=$(sudo pacman -U --noconfirm "$pkg" 2>&1) || fail "reinstall failed: $out"
grep -q "pacman reads $dropin" <<<"$out" || fail "scriptlet did not see the Include: $out"

echo "== guard hook mask"
[[ $(readlink /etc/pacman.d/hooks/00-omarchy-update-guard.hook) == /dev/null ]] || fail "guard hook is not masked"

echo "== stubs"
for shell_cmd in "command -v omarchy-refresh-limine" "sudo sh -c 'command -v omarchy-refresh-limine'"; do
  where=$(eval "$shell_cmd")
  [[ $where == /usr/local/bin/omarchy-refresh-limine ]] || fail "$shell_cmd found $where"
  echo "$shell_cmd -> $where"
done
echo "== migration gate on PATH (shell and systemd user manager, which runs the login notifier)"
[[ $(command -v omarchy-migrate) == /usr/local/bin/omarchy-migrate ]] || fail "omarchy-migrate is not the gate"
user_path=$(systemctl --user show-environment | sed -n 's/^PATH=//p')
[[ -n $user_path ]] || user_path=$(systemd-path search-binaries-default)
[[ $(PATH=$user_path command -v omarchy-migrate) == /usr/local/bin/omarchy-migrate ]] ||
  fail "systemd user PATH ($user_path) does not find the gate first"
echo "systemd user PATH: $user_path"
omarchy-migrate --status || fail "gate --status failed without Omarchy installed"
if out=$(sudo omarchy-snapshot restore 2>&1); then
  fail "omarchy-snapshot restore was not refused"
fi
grep -q 'omarchy-snapshot restore is blocked on CachyOS' <<<"$out" || fail "unexpected stub output: $out"
echo "$out"

echo "== remove with the Include still present"
out=$(sudo pacman -R --noconfirm cachyos-quattro 2>&1) || fail "pacman -R failed: $out"
echo "$out"
grep -q 'pacman will refuse to run' <<<"$out" || fail "pre_remove did not warn"
if out=$(pacman -Q pacman 2>&1); then
  fail "pacman still runs with a dangling Include"
fi
grep -q "config file $dropin could not be read" <<<"$out" || fail "unexpected pacman error: $out"
echo "pacman stopped as expected: $out"
sudo sed -i "\|^$include\$|d" /etc/pacman.conf
pacman -Q pacman >/dev/null || fail "pacman still fails after removing the Include"
echo "guard-package: ok"
