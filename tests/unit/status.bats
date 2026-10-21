#!/usr/bin/env bats
# Stub bodies are single-quoted on purpose: they expand when the stub runs.
# shellcheck disable=SC2016

load helpers

setup() {
  export CQ_ROOT="$BATS_TEST_TMPDIR/root"
  bin=$BATS_TEST_TMPDIR/bin
  mkdir -p "$CQ_ROOT/usr/lib/cachyos-quattro" "$bin"
  printf '#!/bin/bash\necho "ok hooks: fine"\nexit "${FAKE_VERIFY_RC:-0}"\n' >"$CQ_ROOT/usr/lib/cachyos-quattro/verify"
  printf '#!/bin/bash\nexec "$@"\n' >"$bin/sudo"
  printf '#!/bin/bash\nprintf "omarchy 4.0.6-1\\nomarchy-settings 4.0.6-1\\nbash 5.3-1\\n"\n' >"$bin/pacman"
  printf '#!/bin/bash\nprintf "1789325478.sh\\theld\\tunreviewed and can change system state\\n1000000001.sh\\trun\\treviewed\\n"\n' >"$bin/omarchy-migrate"
  chmod +x "$CQ_ROOT/usr/lib/cachyos-quattro/verify" "$bin"/*
  export PATH="$bin:$PATH"
  # shellcheck source=lib/cmd-status.sh
  source "$BATS_TEST_DIRNAME/../../lib/cmd-status.sh"
}

@test "status shows the checks, Omarchy packages and held migrations" {
  run cmd_status
  [ "$status" -eq 0 ]
  [[ $output == *"ok hooks: fine"* ]]
  [[ $output == *"omarchy-settings 4.0.6-1"* ]]
  [[ $output != *"bash 5.3-1"* ]]
  [[ $output == *"1789325478.sh  unreviewed and can change system state"* ]]
  [[ $output != *"1000000001.sh"* ]]
  [[ $output == *"pacman -Qkk omarchy-settings"* ]]
}

@test "status returns 1 when a check fails" {
  FAKE_VERIFY_RC=1 run cmd_status
  [ "$status" -eq 1 ]
}
