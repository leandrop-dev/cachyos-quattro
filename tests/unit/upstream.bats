#!/usr/bin/env bats
# Synthetic package contents are single-quoted on purpose.
# shellcheck disable=SC2016

load helpers

TOOLS="$BATS_TEST_DIRNAME/../../tools"

# mktree <dir> <version>: a minimal extracted Omarchy release.
mktree() {
  local t=$1 v=$2
  mkdir -p "$t/omarchy/usr/bin" "$t/omarchy/usr/share/omarchy/migrations" "$t/omarchy/usr/share/omarchy/install/config" \
    "$t/omarchy/usr/share/omarchy/install/hardware" "$t/omarchy/usr/share/omarchy/install/login" \
    "$t/omarchy/usr/share/omarchy/install/post-install" "$t/omarchy-settings/etc/mkinitcpio.conf.d"
  printf 'pkgname = omarchy\npkgver = %s-1\ndepend = limine\n' "$v" >"$t/omarchy/.PKGINFO"
  printf 'pkgname = omarchy-settings\npkgver = %s-1\nbackup = etc/x.conf\n' "$v" >"$t/omarchy-settings/.PKGINFO"
  printf 'post_install() {\n  rm -f /etc/os-release\n}\n' >"$t/omarchy-settings/.INSTALL"
  printf '#!/bin/bash\n# omarchy:summary=migrate\nfor m in migrations; do :; done\n' >"$t/omarchy/usr/bin/omarchy-migrate"
  printf '#!/bin/bash\n# omarchy:summary=root\n# omarchy:requires-sudo=true\n' >"$t/omarchy/usr/bin/omarchy-needs-root"
  printf 'echo "Tidy the user config"\nmkdir -p ~/.config/x\n' >"$t/omarchy/usr/share/omarchy/migrations/1000.sh"
  printf 'HOOKS=(base udev encrypt)\n' >"$t/omarchy-settings/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
  local g
  for g in config hardware login post-install; do
    printf 'run_logged "$OMARCHY_INSTALL/%s/a.sh"\n' "$g" >"$t/omarchy/usr/share/omarchy/install/$g/all.sh"
    echo 'true' >"$t/omarchy/usr/share/omarchy/install/$g/a.sh"
  done
  printf 'hyprland\nsddm\n' >"$t/omarchy/usr/share/omarchy/install/omarchy-base.packages"
}

setup() {
  OLD=$BATS_TEST_TMPDIR/old
  NEW=$BATS_TEST_TMPDIR/new
  L=$BATS_TEST_TMPDIR/ledger
  mktree "$OLD" 1.0.0
  mktree "$NEW" 1.1.0
  mkdir -p "$L"
  printf 'etc/mkinitcpio.conf.d/omarchy_hooks.conf\tnoextract\treplaces HOOKS\n' >"$L/files.tsv"
  printf '1000.sh\t%s\trun\treviewed\n' "$(sha256sum "$OLD/omarchy/usr/share/omarchy/migrations/1000.sh" | cut -d' ' -f1)" >"$L/migrations.tsv"
  printf 'config/a.sh\trun\tx\nhardware/a.sh\trun\tx\nlogin/a.sh\trun\tx\npost-install/a.sh\trun\tx\n' >"$L/install-steps.tsv"
  printf '1.0.0\t2026-10-21\treviewed\n' >"$L/releases.tsv"
}

@test "ledger-scan writes every ledger file for a tree" {
  run "$TOOLS/ledger-scan" "$OLD" "$BATS_TEST_TMPDIR/scan"
  [ "$status" -eq 0 ]
  for f in files install packages migrations commands; do
    ls "$BATS_TEST_TMPDIR/scan/$f.1.0.0".*
  done
  grep -qP '^omarchy-needs-root\tyes$' "$BATS_TEST_TMPDIR/scan/commands.1.0.0.tsv"
  grep -qP '^etc/mkinitcpio.conf.d/omarchy_hooks.conf\tomarchy-settings\tno\t' "$BATS_TEST_TMPDIR/scan/files.1.0.0.tsv"
}

@test "the report flags a new mkinitcpio drop-in as boot-sensitive and unreviewed" {
  echo 'HOOKS+=(more)' >"$NEW/omarchy-settings/etc/mkinitcpio.conf.d/omarchy_new.conf"
  run "$TOOLS/upstream-diff" "$L" "$OLD" "$NEW"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ $output == *"# Omarchy 1.0.0 → 1.1.0"* ]]
  grep -qE '^\| new \| `etc/mkinitcpio.conf.d/omarchy_new.conf` \| omarchy-settings \| boot-sensitive, not in files.tsv \|$' <<<"$output"
}

@test "the report flags a reviewed migration whose content changed" {
  echo 'sudo true' >>"$NEW/omarchy/usr/share/omarchy/migrations/1000.sh"
  run "$TOOLS/upstream-diff" "$L" "$OLD" "$NEW"
  [ "$status" -eq 0 ]
  grep -qE '^\| changed \| `1000.sh` \| yes \| reviewed as run; the gate holds it until re-reviewed \|$' <<<"$output"
}

@test "the report shows a new privileged migration in full" {
  printf 'echo "Move the boot order"\nsudo sed -i /BOOT_ORDER/d /etc/default/limine\n' >"$NEW/omarchy/usr/share/omarchy/migrations/2000.sh"
  run "$TOOLS/upstream-diff" "$L" "$OLD" "$NEW"
  [ "$status" -eq 0 ]
  grep -qE '^\| new \| `2000.sh` \| yes \| Move the boot order \|$' <<<"$output"
  [[ $output == *"sudo sed -i /BOOT_ORDER/d /etc/default/limine"* ]]
}

@test "the report diffs .INSTALL, dependencies, watched commands, install steps and base packages" {
  printf 'post_install() {\n  rm -f /etc/os-release\n  cp -f x /etc/fstab\n}\n' >"$NEW/omarchy-settings/.INSTALL"
  echo 'depend = grub' >>"$NEW/omarchy/.PKGINFO"
  echo 'omarchy-refresh-limine' >>"$NEW/omarchy/usr/bin/omarchy-migrate"
  printf 'run_logged "$OMARCHY_INSTALL/config/new.sh"\n' >>"$NEW/omarchy/usr/share/omarchy/install/config/all.sh"
  echo 'efibootmgr --create' >"$NEW/omarchy/usr/share/omarchy/install/config/new.sh"
  echo 'linux-omarchy' >>"$NEW/omarchy/usr/share/omarchy/install/omarchy-base.packages"
  run "$TOOLS/upstream-diff" "$L" "$OLD" "$NEW"
  [ "$status" -eq 0 ]
  [[ $output == *"+  cp -f x /etc/fstab"* ]]
  [[ $output == *$'+omarchy\tdepend\tgrub'* ]]
  [[ $output == *"+omarchy-refresh-limine"* ]]
  grep -qE '^\| new \| `config/new.sh` \| not in install-steps.tsv \|$' <<<"$output"
  [[ $output == *"+linux-omarchy"* ]]
}

@test "the report lists a new command with requires-sudo" {
  printf '#!/bin/bash\n# omarchy:requires-sudo=true\nlimine-update\n' >"$NEW/omarchy/usr/bin/omarchy-boot-thing"
  run "$TOOLS/upstream-diff" "$L" "$OLD" "$NEW"
  [ "$status" -eq 0 ]
  grep -qE '^\| new \| `omarchy-boot-thing` \| yes \| limine \|$' <<<"$output"
}

@test "an unchanged release produces no findings" {
  run "$TOOLS/upstream-diff" "$L" "$OLD" "$OLD"
  [ "$status" -eq 0 ]
  [[ $output == *"No changes in the areas cachyos-quattro reviews."* ]]
}

# mkdb <file> <version>: an omarchy.db holding only the omarchy package at <version>.
mkdb() {
  local d=$BATS_TEST_TMPDIR/db
  rm -rf "$d"
  mkdir -p "$d/omarchy-$2-1" "$d/omarchy-settings-$2-1"
  printf '%%NAME%%\nomarchy\n\n%%VERSION%%\n%s-1\n' "$2" >"$d/omarchy-$2-1/desc"
  printf '%%NAME%%\nomarchy-settings\n\n%%VERSION%%\n%s-1\n' "$2" >"$d/omarchy-settings-$2-1/desc"
  (cd "$d" && bsdtar -czf "$1" .)
}

@test "upstream-check prints a newer stable version and is silent for the reviewed one" {
  mkdb "$BATS_TEST_TMPDIR/new.db" 1.0.1
  run "$TOOLS/upstream-check" "$BATS_TEST_TMPDIR/new.db" "$L/releases.tsv"
  [ "$status" -eq 0 ]
  [ "$output" = 1.0.1 ]
  mkdb "$BATS_TEST_TMPDIR/same.db" 1.0.0
  run "$TOOLS/upstream-check" "$BATS_TEST_TMPDIR/same.db" "$L/releases.tsv"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "upstream-early reports migrations between the reviewed tag and a pre-release from git" {
  local src=$BATS_TEST_TMPDIR/src
  mkdir -p "$src/migrations" "$src/bin"
  git -C "$src" init -q
  git -C "$src" config user.email t@example.invalid
  git -C "$src" config user.name t
  printf '#!/bin/bash\n# omarchy:requires-sudo=true\n' >"$src/bin/omarchy-needs-root"
  echo 'echo "Tidy"' >"$src/migrations/1000.sh"
  git -C "$src" add -A
  git -C "$src" commit -qm one
  git -C "$src" tag v1.0.0
  echo 'omarchy-needs-root' >>"$src/migrations/1000.sh"
  echo 'echo "User only"' >"$src/migrations/2000.sh"
  git -C "$src" add -A
  git -C "$src" commit -qm two
  git -C "$src" tag v1.1.0-rc1
  run "$TOOLS/upstream-early" "$src" v1.0.0 v1.1.0-rc1
  echo "$output"
  [ "$status" -eq 0 ]
  grep -qE '^\| changed \| `1000.sh` \| yes \|' <<<"$output"
  grep -qE '^\| new \| `2000.sh` \| no \|' <<<"$output"
}

@test "the report shows calls that bypass the gate, not mentions of a name" {
  printf '#!/bin/bash\nexport PATH="$OMARCHY_PATH/bin:$PATH"\nusage() { echo "Usage: omarchy-channel-x"; }\n# omarchy-migrate runs later\nomarchy-refresh-limine --yes\n' \
    >"$NEW/omarchy/usr/bin/omarchy-channel-x"
  run "$TOOLS/upstream-diff" "$L" "$OLD" "$NEW"
  [ "$status" -eq 0 ]
  [[ $output == *"omarchy-channel-x:5:omarchy-refresh-limine --yes"* ]]
  [[ $output != *"omarchy-channel-x:3:"* ]]
  [[ $output != *"omarchy-channel-x:4:"* ]]
}

# fake_gh: a gh that knows the issue titles in $GH_TITLES and records what it is asked.
fake_gh() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/bin/bash
echo "gh $*" >>"$BATS_TEST_TMPDIR/gh.log"
case "$1 $2" in
"issue list") printf '%s\n' "${GH_TITLES:-}" ;;
"issue create")
  while (($#)); do [[ $1 == --body-file ]] && cp "$2" "$BATS_TEST_TMPDIR/body.md"; shift; done ;;
esac
GH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "upstream-issue opens a labelled issue once per title" {
  fake_gh
  echo '# report' >"$BATS_TEST_TMPDIR/r.md"
  run "$TOOLS/upstream-issue" "Review Omarchy 1.1.0" "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
  grep -q 'gh issue create --title Review Omarchy 1.1.0 --label upstream-release' "$BATS_TEST_TMPDIR/gh.log"
  GH_TITLES="Review Omarchy 1.1.0" run "$TOOLS/upstream-issue" "Review Omarchy 1.1.0" "$BATS_TEST_TMPDIR/r.md"
  [ "$status" -eq 0 ]
  [[ $output == *"exists; not opening another"* ]]
  [ "$(grep -c 'issue create' "$BATS_TEST_TMPDIR/gh.log")" -eq 1 ]
}

@test "upstream-issue cuts a report over GitHub's body limit and links the full one" {
  fake_gh
  for _ in $(seq 2000); do echo "| new | \`0000000000.sh\` | yes | a migration summary line |"; done >"$BATS_TEST_TMPDIR/big.md"
  run "$TOOLS/upstream-issue" "Early warning: Omarchy v9" "$BATS_TEST_TMPDIR/big.md" "https://example.invalid/run/1"
  [ "$status" -eq 0 ]
  [ "$(wc -c <"$BATS_TEST_TMPDIR/body.md")" -lt 65536 ]
  grep -q 'Report truncated.*Full report: https://example.invalid/run/1' "$BATS_TEST_TMPDIR/body.md"
}
