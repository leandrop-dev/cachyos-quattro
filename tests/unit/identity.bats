#!/usr/bin/env bats

load helpers

RESTORE="$BATS_TEST_DIRNAME/../../package/libexec/restore-identity"

save_identity() {
  mkdir -p "$CQ_ROOT/var/lib/cachyos-quattro/identity"
  cp "$CQ_ROOT/etc/os-release" "$CQ_ROOT/etc/nsswitch.conf" "$CQ_ROOT/var/lib/cachyos-quattro/identity/"
}

@test "restores os-release and nsswitch.conf that omarchy-settings overwrote" {
  mkroot cachyos-limine-plain
  save_identity
  printf 'NAME="Omarchy"\nID=omarchy\n' >"$CQ_ROOT/etc/os-release"
  printf 'hosts: files dns\n' >"$CQ_ROOT/etc/nsswitch.conf"
  chmod 0600 "$CQ_ROOT/etc/os-release"

  run "$RESTORE"
  [ "$status" -eq 0 ]
  cmp "$CQ_ROOT/etc/os-release" "$FIXTURES_DIR/cachyos-limine-plain/etc/os-release"
  cmp "$CQ_ROOT/etc/nsswitch.conf" "$FIXTURES_DIR/cachyos-limine-plain/etc/nsswitch.conf"
  [ "$(stat -c %a "$CQ_ROOT/etc/os-release")" = 644 ]
  grep -q 'restored etc/os-release' "$CQ_ROOT/var/log/cachyos-quattro.log"
  grep -q 'restored etc/nsswitch.conf' "$CQ_ROOT/var/log/cachyos-quattro.log"
}

@test "restores os-release that omarchy-settings removed" {
  mkroot cachyos-limine-luks
  save_identity
  rm "$CQ_ROOT/etc/os-release"

  run "$RESTORE"
  [ "$status" -eq 0 ]
  grep -qx 'ID=cachyos' "$CQ_ROOT/etc/os-release"
}

@test "leaves identical files alone" {
  mkroot cachyos-limine-plain
  save_identity
  touch -d '2020-01-01' "$CQ_ROOT/etc/os-release" "$CQ_ROOT/etc/nsswitch.conf"

  run "$RESTORE"
  [ "$status" -eq 0 ]
  [ "$(stat -c %Y "$CQ_ROOT/etc/os-release")" = "$(date -d '2020-01-01' +%s)" ]
  [ "$(stat -c %Y "$CQ_ROOT/etc/nsswitch.conf")" = "$(date -d '2020-01-01' +%s)" ]
  [ ! -e "$CQ_ROOT/var/log/cachyos-quattro.log" ]
}

@test "warns and exits 0 when no saved copy exists" {
  mkroot cachyos-limine-plain
  printf 'ID=omarchy\n' >"$CQ_ROOT/etc/os-release"

  run "$RESTORE"
  [ "$status" -eq 0 ]
  [[ $output == *"no saved copy of etc/os-release"* ]]
  [[ $output == *"no saved copy of etc/nsswitch.conf"* ]]
  grep -qx 'ID=omarchy' "$CQ_ROOT/etc/os-release"
}
