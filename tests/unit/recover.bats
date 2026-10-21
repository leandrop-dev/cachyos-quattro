#!/usr/bin/env bats

# Stub bodies are single-quoted on purpose: they expand when the stub runs.
# shellcheck disable=SC2016

load helpers

setup() {
  export CQ_ROOT=
  export CQ_REPO="$BATS_TEST_DIRNAME/../.."
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\n[[ $1 == true ]] && exit 0\nexec "$@"\n' >"$BATS_TEST_TMPDIR/bin/sudo"
  chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # shellcheck source=lib/common.sh
  source "$CQ_REPO/lib/common.sh"
  # shellcheck source=lib/cmd-recover.sh
  source "$CQ_REPO/lib/cmd-recover.sh"

  # A backup taken from the fixture, and a mounted target that install then broke.
  B=$BATS_TEST_TMPDIR/backup
  T=$BATS_TEST_TMPDIR/mnt
  mkdir -p "$B" "$T"
  cp -a "$FIXTURES_DIR/cachyos-limine-luks/." "$T/"
  tar -cpf "$B/boot.tar" -C "$T" boot
  tar -cpf "$B/etc.tar" -C "$T" etc/os-release etc/nsswitch.conf etc/mkinitcpio.conf etc/mkinitcpio.conf.d
  printf '/etc/limine-entry-tool.d\n' >"$B/missing.txt"
  echo 'HOOKS=(base udev encrypt filesystems)' >"$T/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
  mkdir -p "$T/etc/limine-entry-tool.d"
  echo 'TARGET_OS_NAME="Omarchy"' >"$T/etc/limine-entry-tool.d/omarchy-defaults.conf"
  printf 'ID=omarchy\n' >"$T/etc/os-release"
  echo broken >"$T/boot/limine.conf"
}

@test "recover restores /boot and /etc into the target and removes Omarchy's boot files" {
  run cmd_recover --backup "$B" --target "$T"
  echo "$output"
  [ "$status" -eq 0 ]
  cmp "$T/boot/limine.conf" "$FIXTURES_DIR/cachyos-limine-luks/boot/limine.conf"
  cmp "$T/etc/os-release" "$FIXTURES_DIR/cachyos-limine-luks/etc/os-release"
  [ ! -e "$T/etc/mkinitcpio.conf.d/omarchy_hooks.conf" ]
  [ ! -e "$T/etc/limine-entry-tool.d/omarchy-defaults.conf" ]
  [[ $output == *"arch-chroot $T limine-mkinitcpio"* ]]
}

@test "recover refuses a directory that is not a backup" {
  rm "$B/boot.tar"
  run cmd_recover --backup "$B" --target "$T"
  [ "$status" -eq 1 ]
  [[ $output == *"no boot.tar"* ]]
}

@test "recover needs --backup" {
  run cmd_recover --target "$T"
  [ "$status" -eq 1 ]
  [[ $output == *"--backup"* ]]
}
