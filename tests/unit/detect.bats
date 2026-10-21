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
}

@test "a stock Limine+LUKS install is detected as such" {
  fake_system cachyos-limine-luks
  [ "$(cq_bootloader)" = limine ]
  [ "$(cq_root_luks)" = yes ]
  [ "$(cq_luks_style)" = systemd ]
  [ "$(cq_root_fs)" = btrfs ]
  [ "$(cq_snapper_configs)" = root ]
  [ "$(cq_home_separate)" = yes ]
  [ "$(cq_desktop_present)" = no ]
  [ "$(cq_omarchy_present)" = no ]
}

@test "a Limine install without LUKS has no LUKS style" {
  fake_system cachyos-limine-plain
  [ "$(cq_root_luks)" = no ]
  [ "$(cq_luks_style)" = none ]
}

@test "cryptdevice= on the command line is the legacy LUKS style" {
  fake_system cachyos-limine-luks
  echo 'rw cryptdevice=UUID=0:root root=/dev/mapper/root' >"$CQ_ROOT/proc/cmdline"
  [ "$(cq_luks_style)" = legacy ]
}

@test "boot loaders: GRUB, systemd-boot, several, none" {
  fake_system cachyos-limine-luks
  rm "$CQ_ROOT/boot/limine.conf"
  mkdir -p "$CQ_ROOT/boot/grub"
  touch "$CQ_ROOT/boot/grub/grub.cfg"
  echo grub >>"$FAKE_DIR/packages"
  [ "$(cq_bootloader)" = grub ]
  export FAKE_BOOTCTL_RC=0
  [ "$(cq_bootloader)" = multiple ]
  rm "$CQ_ROOT/boot/grub/grub.cfg"
  [ "$(cq_bootloader)" = systemd-boot ]
  export FAKE_BOOTCTL_RC=1
  [ "$(cq_bootloader)" = unknown ]
}

@test "limine.conf without the limine package is not Limine" {
  fake_system cachyos-limine-luks
  sed -i '/^limine$/d' "$FAKE_DIR/packages"
  [ "$(cq_bootloader)" = unknown ]
}

@test "a display manager or desktop package counts as a desktop" {
  fake_system cachyos-limine-luks
  mkdir -p "$CQ_ROOT/etc/systemd/system"
  ln -s /usr/lib/systemd/system/sddm.service "$CQ_ROOT/etc/systemd/system/display-manager.service"
  [ "$(cq_desktop_present)" = yes ]
  rm "$CQ_ROOT/etc/systemd/system/display-manager.service"
  echo plasma-desktop >>"$FAKE_DIR/packages"
  [ "$(cq_desktop_present)" = yes ]
}

@test "Omarchy is present when installed or when ~/.local/share/omarchy exists" {
  fake_system cachyos-limine-luks
  mkdir -p "$HOME/.local/share/omarchy"
  [ "$(cq_omarchy_present)" = yes ]
  rm -r "$HOME/.local/share/omarchy"
  echo omarchy >>"$FAKE_DIR/packages"
  [ "$(cq_omarchy_present)" = yes ]
}

@test "/home on the root subvolume is not separate" {
  fake_system cachyos-limine-luks
  export FAKE_HOME_FSROOT=
  [ "$(cq_home_separate)" = no ]
}
