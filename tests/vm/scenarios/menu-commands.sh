#!/bin/bash
# Runs on the guest: after install, every stubbed Omarchy command refuses with its explanation,
# `omarchy-snapshot create` still works, and the allowed Plymouth theme command rebuilds the
# initramfs with CachyOS's HOOKS (verify passes afterwards).

set -euo pipefail

fail() {
  echo "menu-commands: $*" >&2
  exit 1
}

bash tests/vm/guest/install-omarchy.sh || fail "install failed"
# Omarchy's commands read OMARCHY_PATH, which its login profile sets.
# shellcheck disable=SC1091
. /usr/share/omarchy/default/bash/env-bootstrap

echo "== stubbed commands"
while read -r name; do
  [[ $(command -v "$name") == /usr/local/bin/$name ]] || fail "$name does not resolve to the stub"
  cmd=("$name")
  [[ $name != omarchy-snapshot ]] || cmd+=(restore)
  if out=$("${cmd[@]}" 2>&1 </dev/null); then fail "${cmd[*]} ran"; fi
  grep -q "^${cmd[*]} is blocked on CachyOS: " <<<"$out" || fail "${cmd[*]}: unexpected output: $out"
  echo "refused: ${cmd[*]}"
done < <(grep -v '^#' package/stubbed-commands.txt)
omarchy-snapshot create || fail "omarchy-snapshot create failed"

echo "== omarchy-plymouth-set-by-theme"
theme=$(find /usr/share/omarchy/themes -mindepth 1 -maxdepth 1 -type d -name 'tokyo*' -printf '%f\n' | head -n1)
[[ -n $theme ]] || fail "no tokyo theme in /usr/share/omarchy/themes"
omarchy-plymouth-set-by-theme "$theme" </dev/null || fail "omarchy-plymouth-set-by-theme $theme failed"
out=$(sudo /usr/lib/cachyos-quattro/verify) || fail "verify failed after the Plymouth rebuild: $out"
echo "$out" | grep -E '^ok (hooks|initramfs):'
echo "menu-commands: ok"
