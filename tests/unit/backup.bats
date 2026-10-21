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
  # shellcheck source=lib/cmd-backup.sh
  source "$BATS_TEST_DIRNAME/../../lib/cmd-backup.sh"
}

backup_dir() {
  readlink -f "$HOME/.local/state/cachyos-quattro/backups/latest"
}

@test "backup writes every listed file and a manifest whose hashes verify" {
  fake_system cachyos-limine-luks
  mkdir -p "$HOME/.config/fish"
  echo 'set -g x 1' >"$HOME/.config/fish/config.fish"
  run cmd_backup
  echo "$output"
  [ "$status" -eq 0 ]
  dir=$(backup_dir)
  for f in snapshot.txt boot.tar etc.tar home.tar cmdline.txt pacman-Qqe.txt enabled-units.txt missing.txt manifest.sha256; do
    [ -f "$dir/$f" ] || { echo "missing $f"; false; }
  done
  [ "$(cat "$dir/snapshot.txt")" = 42 ]
  grep -q -- '--description cachyos-quattro pre-install' "$FAKE_DIR/snapper.log"
  tar -tf "$dir/boot.tar" | grep -qx 'boot/limine.conf'
  tar -tf "$dir/etc.tar" | grep -qx 'etc/mkinitcpio.conf'
  tar -tf "$dir/home.tar" | grep -qx '.config/fish/config.fish'
  (cd "$dir" && sha256sum -c --quiet manifest.sha256)
  [ "$(stat -c %a "$dir")" = 700 ]
}

@test "paths that do not exist are skipped and listed" {
  fake_system cachyos-limine-luks
  run cmd_backup
  [ "$status" -eq 0 ]
  dir=$(backup_dir)
  grep -qx '/etc/sddm.conf.d' "$dir/missing.txt"
  grep -qx '/etc/limine-entry-tool.d' "$dir/missing.txt"
  grep -qx "$HOME/.bashrc" "$dir/missing.txt"
}

@test "pacman's keyring is not copied into the backup" {
  fake_system cachyos-limine-luks
  mkdir -p "$CQ_ROOT/etc/pacman.d/gnupg"
  echo secret >"$CQ_ROOT/etc/pacman.d/gnupg/secring.gpg"
  run cmd_backup
  [ "$status" -eq 0 ]
  run grep -c gnupg <(tar -tf "$(backup_dir)/etc.tar")
  [ "$output" = 0 ]
}

@test "baselines and identity copies match what verify compares" {
  fake_system cachyos-limine-luks
  run cmd_backup
  [ "$status" -eq 0 ]
  lib=$CQ_ROOT/var/lib/cachyos-quattro
  [ "$(cat "$lib/baseline/hooks")" = "base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth sd-encrypt filesystems sd-btrfs-overlayfs" ]
  grep -qx 'BOOT_ORDER=\*, \*lts, \*fallback, Snapshots' "$lib/baseline/limine"
  grep -qx $'linux-cachyos\tCachyOS <admin@cachyos.org>' "$lib/baseline/packagers"
  cmp "$lib/baseline/cmdline" "$CQ_ROOT/proc/cmdline"
  cmp "$lib/identity/os-release" "$CQ_ROOT/etc/os-release"
  cmp "$lib/identity/nsswitch.conf" "$CQ_ROOT/etc/nsswitch.conf"
  [ -f "$(backup_dir)/baseline/hooks" ]
}

@test "backup refuses when os-release is not CachyOS" {
  fake_system cachyos-limine-luks
  printf 'ID=omarchy\n' >"$CQ_ROOT/etc/os-release"
  run cmd_backup
  [ "$status" -eq 1 ]
  [[ $output == *"not CachyOS"* ]]
  [ ! -e "$CQ_ROOT/var/lib/cachyos-quattro/identity/os-release" ]
}
