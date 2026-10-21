#!/usr/bin/env bats

# Stub bodies are single-quoted on purpose: they expand when the stub runs.
# shellcheck disable=SC2016

load helpers

setup() {
  export CQ_ROOT="$BATS_TEST_TMPDIR/root"
  export CQ_REPO="$BATS_TEST_DIRNAME/../.."
  mkdir -p "$CQ_ROOT"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nexec "$@"\n' >"$BATS_TEST_TMPDIR/bin/sudo"
  chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # shellcheck source=lib/common.sh
  source "$CQ_REPO/lib/common.sh"
  # shellcheck source=lib/cmd-uninstall.sh
  source "$CQ_REPO/lib/cmd-uninstall.sh"
  B=$BATS_TEST_TMPDIR/backup
  mkdir -p "$B"
}

@test "units enabled since install are disabled; units enabled before and missing now are re-enabled" {
  printf 'NetworkManager.service enabled disabled\nsshd.service enabled disabled\nufw.service enabled enabled\n' >"$B/enabled-units.txt"
  printf 'NetworkManager.service enabled disabled\nsddm.service enabled disabled\ndocker.socket enabled disabled\nufw.service enabled enabled\n' >"$BATS_TEST_TMPDIR/now.txt"
  run cq_uninstall_units_to_disable "$B/enabled-units.txt" "$BATS_TEST_TMPDIR/now.txt"
  [ "$output" = $'docker.socket\nsddm.service' ]
  run cq_uninstall_units_to_enable "$B/enabled-units.txt" "$BATS_TEST_TMPDIR/now.txt"
  [ "$output" = sshd.service ]
}

@test "the packages to remove are those install added explicitly" {
  printf 'base\nfish\nlimine\nsnapper\n' >"$B/pacman-Qqe.txt"
  printf 'base\nfish\nhyprland\nlimine\nomarchy\nomarchy-keyring\nomarchy-settings\nsnapper\ncachyos-quattro\n' >"$B/installed-packages.txt"
  run cq_uninstall_packages "$B"
  [ "$output" = $'hyprland\nomarchy\nomarchy-keyring\nomarchy-settings' ]
}

@test "the guard package is never in the removal list; it goes last" {
  printf 'base\n' >"$B/pacman-Qqe.txt"
  printf 'base\ncachyos-quattro\nomarchy\n' >"$B/installed-packages.txt"
  run cq_uninstall_packages "$B"
  [ "$output" = omarchy ]
}

@test "/etc files come back from etc.tar and paths that did not exist are removed" {
  mkroot cachyos-limine-luks
  tar -cpf "$B/etc.tar" -C "$CQ_ROOT" etc/os-release etc/nsswitch.conf etc/plymouth
  printf '/etc/sddm.conf.d\n/etc/limine-entry-tool.d\n' >"$B/missing.txt"
  printf 'ID=omarchy\n' >"$CQ_ROOT/etc/os-release"
  mkdir -p "$CQ_ROOT/etc/sddm.conf.d"
  echo '[Autologin]' >"$CQ_ROOT/etc/sddm.conf.d/autologin.conf"
  run cq_uninstall_restore_etc "$B"
  [ "$status" -eq 0 ]
  cmp "$CQ_ROOT/etc/os-release" "$FIXTURES_DIR/cachyos-limine-luks/etc/os-release"
  [ ! -e "$CQ_ROOT/etc/sddm.conf.d" ]
  [[ $output == *"removed /etc/sddm.conf.d"* ]]
}

@test "a path neither in etc.tar nor listed as missing is left alone" {
  mkroot cachyos-limine-luks
  tar -cpf "$B/etc.tar" -C "$CQ_ROOT" etc/os-release
  : >"$B/missing.txt"
  echo 'deny = 10' >"$CQ_ROOT/etc/security/faillock.conf"
  run cq_uninstall_restore_etc "$B"
  [ "$status" -eq 0 ]
  grep -qx 'deny = 10' "$CQ_ROOT/etc/security/faillock.conf"
  [[ $output == *"/etc/security/faillock.conf: not in the backup; left as is"* ]]
}
