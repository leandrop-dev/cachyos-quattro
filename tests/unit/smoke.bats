#!/usr/bin/env bats

load helpers

@test "mkroot copies the Limine+LUKS fixture into CQ_ROOT" {
  mkroot cachyos-limine-luks
  grep -qx 'ID=cachyos' "$CQ_ROOT/etc/os-release"
  grep -q 'rd.luks.uuid=' "$CQ_ROOT/proc/cmdline"
}

@test "mkroot copies the Limine plain fixture into CQ_ROOT" {
  mkroot cachyos-limine-plain
  grep -qx 'ID=cachyos' "$CQ_ROOT/etc/os-release"
  run grep -q 'rd.luks' "$CQ_ROOT/proc/cmdline"
  [ "$status" -eq 1 ]
}

@test "mkroot fails for an unknown fixture" {
  run mkroot no-such-fixture
  [ "$status" -eq 1 ]
  [[ $output == *"no fixture named 'no-such-fixture'"* ]]
}
