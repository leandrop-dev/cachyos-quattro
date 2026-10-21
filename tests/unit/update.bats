#!/usr/bin/env bats
# Stub bodies are single-quoted on purpose: they expand when the stub runs.
# Overrides of cq_guard_outdated are called by cmd_update, which shellcheck cannot see.
# shellcheck disable=SC2016,SC2329

load helpers

setup() {
  export CQ_ROOT="$BATS_TEST_TMPDIR/root"
  export CQ_REPO="$BATS_TEST_DIRNAME/../.."
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\n[[ $1 == true ]] && exit 0\nexec "$@"\n' >"$BATS_TEST_TMPDIR/bin/sudo"
  printf '#!/bin/bash\nset -u\necho "omarchy-update $*" >>"$HOME/calls.log"\necho "$OMARCHY_PATH" >"$HOME/omarchy-path"\n' >"$BATS_TEST_TMPDIR/bin/omarchy-update"
  printf '#!/bin/bash\necho "git $*" >>"$HOME/git.log"\n' >"$BATS_TEST_TMPDIR/bin/git"
  printf '#!/bin/bash\nprintf "1789325478.sh\\theld\\tunreviewed and can change system state\\n"\n' >"$BATS_TEST_TMPDIR/bin/omarchy-migrate"
  chmod +x "$BATS_TEST_TMPDIR/bin"/*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # shellcheck source=lib/common.sh
  source "$CQ_REPO/lib/common.sh"
  # shellcheck source=lib/detect.sh
  source "$CQ_REPO/lib/detect.sh"
  # shellcheck source=lib/cmd-update.sh
  source "$CQ_REPO/lib/cmd-update.sh"
}

# installed_guard: CQ_ROOT holds exactly what the repository's package would install.
installed_guard() {
  local lib=$CQ_ROOT/usr/lib/cachyos-quattro name
  mkdir -p "$lib" "$CQ_ROOT/usr/share/cachyos-quattro/ledger" "$CQ_ROOT/usr/share/libalpm/hooks" \
    "$CQ_ROOT/etc/pacman.d" "$CQ_ROOT/usr/local/bin" "$CQ_ROOT/var/lib/cachyos-quattro"
  cp "$CQ_REPO"/package/libexec/* "$lib/"
  cp "$CQ_REPO"/ledger/*.tsv "$CQ_ROOT/usr/share/cachyos-quattro/ledger/"
  cp "$CQ_REPO"/package/hooks/*.hook "$CQ_ROOT/usr/share/libalpm/hooks/"
  "$CQ_REPO/tools/gen-noextract" "$CQ_REPO/ledger/files.tsv" >"$CQ_ROOT/etc/pacman.d/cachyos-quattro.conf"
  while read -r name; do
    ln -s /usr/lib/cachyos-quattro/stub "$CQ_ROOT/usr/local/bin/$name"
  done < <(grep -v '^#' "$CQ_REPO/package/stubbed-commands.txt")
  touch "$CQ_ROOT/var/lib/cachyos-quattro/installed"
  printf '#!/bin/bash\necho "ok hooks: fine"\nexit "${FAKE_VERIFY_RC:-0}"\n' >"$lib/verify"
  cp "$CQ_REPO/package/libexec/verify" "$BATS_TEST_TMPDIR/real-verify"
}

@test "an installed guard that matches the repository is current" {
  installed_guard
  cp "$BATS_TEST_TMPDIR/real-verify" "$CQ_ROOT/usr/lib/cachyos-quattro/verify"
  run cq_guard_outdated
  [ "$status" -eq 1 ]
}

@test "a changed ledger, a missing script or a missing stub makes the guard outdated" {
  installed_guard
  cp "$BATS_TEST_TMPDIR/real-verify" "$CQ_ROOT/usr/lib/cachyos-quattro/verify"
  echo extra >>"$CQ_ROOT/usr/share/cachyos-quattro/ledger/files.tsv"
  rm "$CQ_ROOT/usr/lib/cachyos-quattro/txn-check"
  rm "$CQ_ROOT/usr/local/bin/omarchy-refresh-limine"
  run cq_guard_outdated
  [ "$status" -eq 0 ]
  [[ $output == *"ledger/files.tsv"* ]]
  [[ $output == *"txn-check"* ]]
  [[ $output == *"omarchy-refresh-limine"* ]]
}

@test "update stops before omarchy-update when a check fails" {
  installed_guard
  cq_guard_outdated() { return 1; }
  FAKE_VERIFY_RC=1 run cmd_update
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/calls.log" ]
  [[ $output == *"ok hooks: fine"* ]]
}

@test "update installs the post-update hook, runs omarchy-update with its arguments, then checks again" {
  installed_guard
  cq_guard_outdated() { return 1; }
  run cmd_update -y
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/calls.log")" = "omarchy-update -y" ]
  [ "$(cat "$HOME/omarchy-path")" = /usr/share/omarchy ]
  grep -q '/usr/lib/cachyos-quattro/verify' "$HOME/.config/omarchy/hooks/post-update.d/cachyos-quattro-verify"
  [ "$(grep -c 'ok hooks: fine' <<<"$output")" -eq 2 ]
  [[ $output == *"1789325478.sh"* ]]
  [[ $output == *"label:upstream-release"* ]]
}

@test "update refuses when cachyos-quattro is not installed" {
  run cmd_update
  [ "$status" -eq 1 ]
  [[ $output == *"not installed"* ]]
}
