#!/usr/bin/env bats

load helpers
load fakes

setup() {
  export CQ_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$CQ_ROOT"
  # shellcheck source=lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=lib/detect.sh
  source "$BATS_TEST_DIRNAME/../../lib/detect.sh"
  # shellcheck source=lib/cmd-preflight.sh
  source "$BATS_TEST_DIRNAME/../../lib/cmd-preflight.sh"
}

@test "a stock Limine+LUKS install passes preflight" {
  fake_system cachyos-limine-luks
  run cmd_preflight
  echo "$output"
  [ "$status" -eq 0 ]
  [[ $output == *"bootloader: limine"* ]]
  [[ $output == *"root LUKS: yes (systemd)"* ]]
  [[ $output != *FAIL* ]]
}

@test "a stock Limine install without LUKS passes preflight" {
  fake_system cachyos-limine-plain
  run cmd_preflight
  [ "$status" -eq 0 ]
}

@test "GRUB refuses" {
  fake_system cachyos-limine-luks
  rm "$CQ_ROOT/boot/limine.conf"
  mkdir -p "$CQ_ROOT/boot/grub"
  touch "$CQ_ROOT/boot/grub/grub.cfg"
  echo grub >>"$FAKE_DIR/packages"
  run cmd_preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL boot loader is grub"* ]]
}

@test "an installed desktop refuses" {
  fake_system cachyos-limine-luks
  echo sddm >>"$FAKE_DIR/packages"
  run cmd_preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL a desktop is already installed"* ]]
}

@test "LUKS with udev and encrypt HOOKS but an rd.luks command line refuses" {
  fake_system cachyos-limine-luks
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode kms modconf block keyboard keymap consolefont plymouth encrypt filesystems)/' \
    "$CQ_ROOT/etc/mkinitcpio.conf"
  run cmd_preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL LUKS root unlocks with rd.luks (systemd) but HOOKS lack sd-encrypt"* ]]
}

@test "every failed requirement is reported, not just the first" {
  fake_system cachyos-limine-luks
  printf 'ID=arch\n' >"$CQ_ROOT/etc/os-release"
  export FAKE_FREE_GIB=4 FAKE_CURL_RC=7
  echo omarchy >>"$FAKE_DIR/packages"
  : >"$FAKE_DIR/snapper-configs"
  run cmd_preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL /etc/os-release is not CachyOS"* ]]
  [[ $output == *"FAIL Omarchy is already installed"* ]]
  [[ $output == *"FAIL no snapper config named root"* ]]
  [[ $output == *"FAIL only 4 GiB free on /"* ]]
  [[ $output == *"FAIL https://pkgs.omarchy.org/x86_64/omarchy.db is not reachable"* ]]
}

@test "a non-btrfs root refuses" {
  fake_system cachyos-limine-luks
  export FAKE_ROOT_FS=ext4
  run cmd_preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL root file system is ext4, not btrfs"* ]]
}

@test "no sudo stops preflight before any check" {
  fake_system cachyos-limine-luks
  export FAKE_SUDO_RC=1
  run cmd_preflight
  [ "$status" -eq 1 ]
  [[ $output == *"needs sudo"* ]]
  [[ $output != *"bootloader:"* ]]
}
