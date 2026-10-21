#!/usr/bin/env bats

load helpers

CLI="$BATS_TEST_DIRNAME/../../bin/cachyos-quattro"

@test "help lists the commands" {
  run "$CLI" help
  [ "$status" -eq 0 ]
  for cmd in preflight backup install status update uninstall recover; do
    [[ $output == *"$cmd"* ]]
  done
}

@test "no command prints help" {
  run "$CLI"
  [ "$status" -eq 0 ]
  [[ $output == *"Usage: cachyos-quattro"* ]]
}

@test "an unknown command exits 2 with usage" {
  run "$CLI" frobnicate
  [ "$status" -eq 2 ]
  [[ $output == *"Usage: cachyos-quattro"* ]]
}

@test "recover without --backup says what it needs" {
  run "$CLI" recover
  [ "$status" -eq 1 ]
  [[ $output == *"--backup <dir> is required"* ]]
}

@test "status dispatches to cmd_status" {
  mkdir -p "$CQ_ROOT/usr/lib/cachyos-quattro" "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\necho "ok hooks: fine"\n' >"$CQ_ROOT/usr/lib/cachyos-quattro/verify"
  printf '#!/bin/bash\nexec "$@"\n' >"$BATS_TEST_TMPDIR/bin/sudo"
  printf '#!/bin/bash\necho "bash 5.3-1"\n' >"$BATS_TEST_TMPDIR/bin/pacman"
  printf '#!/bin/bash\ntrue\n' >"$BATS_TEST_TMPDIR/bin/omarchy-migrate"
  chmod +x "$CQ_ROOT/usr/lib/cachyos-quattro/verify" "$BATS_TEST_TMPDIR/bin"/*
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run "$CLI" status
  [ "$status" -eq 0 ]
  [[ $output == *"ok hooks: fine"* ]]
}
