#!/usr/bin/env bats
# Migration bodies are single-quoted on purpose: they expand when the migration runs.
# shellcheck disable=SC2016

load helpers
bats_require_minimum_version 1.5.0

GATE="$BATS_TEST_DIRNAME/../../package/libexec/migrate-gate"

setup() {
  export CQ_ROOT="$BATS_TEST_TMPDIR/root"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMARCHY_PATH="$BATS_TEST_TMPDIR/omarchy"
  unset OMARCHY_MIGRATION_STATE DBUS_SESSION_BUS_ADDRESS
  SHARE="$CQ_ROOT/usr/share/cachyos-quattro"
  STATE="$HOME/.local/state/omarchy/migrations"
  mkdir -p "$SHARE/ledger" "$SHARE/migrations" "$HOME" "$OMARCHY_PATH/migrations" "$OMARCHY_PATH/bin" "$OMARCHY_PATH/default"
  printf '# name\tsha256\tverdict\treason\n' >"$SHARE/ledger/migrations.tsv"
  printf '#!/bin/bash\n# omarchy:summary=needs root\n# omarchy:requires-sudo=true\n' >"$OMARCHY_PATH/bin/omarchy-needs-root"
  printf '#!/bin/bash\n# omarchy:summary=user only\n' >"$OMARCHY_PATH/bin/omarchy-user-thing"
}

# migration <name> [body]: an Omarchy migration that records that it ran, then runs body.
migration() {
  printf 'echo "ran %s" >>"$HOME/ran.log"\n%s\n' "$1" "${2:-}" >"$OMARCHY_PATH/migrations/$1.sh"
}

# review <name> <verdict>: a ledger row keyed by the migration's current sha256.
review() {
  local sum
  sum=$(sha256sum "$OMARCHY_PATH/migrations/$1.sh" | cut -d' ' -f1)
  printf '%s.sh\t%s\t%s\ttest\n' "$1" "$sum" "$2" >>"$SHARE/ledger/migrations.tsv"
}

ran() { grep -qx "ran $1" "$HOME/ran.log"; }
marked() { [ -f "$STATE/$1.sh" ]; }
not_ran() { ! grep -qx "ran $1" "$HOME/ran.log"; }
not_marked() { [ ! -f "$STATE/$1.sh" ]; }

@test "a reviewed run migration runs and is marked" {
  migration 1000000001
  review 1000000001 run
  run "$GATE"
  [ "$status" -eq 0 ]
  ran 1000000001
  marked 1000000001
}

@test "a reviewed skip migration is marked without running" {
  migration 1000000002
  review 1000000002 skip
  run "$GATE"
  [ "$status" -eq 0 ]
  not_ran 1000000002
  marked 1000000002
}

@test "a reviewed replace migration runs our script instead" {
  migration 1000000003
  review 1000000003 replace
  printf 'echo "ran replacement" >>"$HOME/ran.log"\n' >"$SHARE/migrations/1000000003.sh"
  run "$GATE"
  [ "$status" -eq 0 ]
  not_ran 1000000003
  ran replacement
  marked 1000000003
}

@test "a replace verdict without our script is held" {
  migration 1000000004
  review 1000000004 replace
  run "$GATE"
  [ "$status" -eq 0 ]
  not_ran 1000000004
  not_marked 1000000004
  [[ $output == *"1000000004.sh"* ]]
}

@test "an unreviewed migration that edits boot settings with sudo is held and logged" {
  migration 1789325478 "sudo sed -i '/^BOOT_ORDER=/d' /etc/default/limine"
  run "$GATE"
  [ "$status" -eq 0 ]
  not_ran 1789325478
  not_marked 1789325478
  [[ $output == *"held"*"1789325478.sh"* ]]
  grep -q 'held 1789325478.sh' "$HOME/.local/state/cachyos-quattro/held.log"
}

@test "an unreviewed user-level migration runs" {
  migration 1000000005 'mkdir -p "$HOME/.config/thing"'
  run "$GATE"
  [ "$status" -eq 0 ]
  ran 1000000005
  marked 1000000005
}

@test "unreviewed migrations are held for pkexec, as_root, omarchy-pkg-* and requires-sudo helpers" {
  migration 1000000011 'pkexec true'
  migration 1000000012 'as_root true'
  migration 1000000013 'omarchy-pkg-add foo'
  migration 1000000014 'omarchy-needs-root'
  migration 1000000015 'omarchy-user-thing'
  run "$GATE" --status
  [ "$status" -eq 0 ]
  for n in 1000000011 1000000012 1000000013 1000000014; do
    grep -qE "^$n\.sh	held	" <<<"$output"
  done
  grep -qE "^1000000015\.sh	run	" <<<"$output"
}

@test "a reviewed migration whose sha256 changed is held" {
  migration 1000000006
  review 1000000006 run
  echo 'echo changed' >>"$OMARCHY_PATH/migrations/1000000006.sh"
  run "$GATE"
  [ "$status" -eq 0 ]
  not_ran 1000000006
  not_marked 1000000006
}

@test "a preseed migration that is somehow pending counts as unreviewed" {
  migration 1000000007 'sudo true'
  review 1000000007 preseed
  migration 1000000008
  review 1000000008 preseed
  run "$GATE"
  [ "$status" -eq 0 ]
  not_marked 1000000007
  ran 1000000008
  marked 1000000008
}

@test "already-marked migrations are left alone" {
  migration 1000000009 'sudo true'
  mkdir -p "$STATE"
  touch "$STATE/1000000009.sh"
  run "$GATE" --status
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--pending lists runnable migrations on stdout and held ones on stderr" {
  migration 1000000021
  migration 1000000022 'sudo true'
  run --separate-stderr "$GATE" --pending
  [ "$status" -eq 0 ]
  [ "$output" = "1000000021.sh" ]
  [ "$stderr" = "held: 1000000022.sh" ]
}

@test "--pending exits 1 when only held migrations remain" {
  migration 1000000022 'sudo true'
  run "$GATE" --pending
  [ "$status" -eq 1 ]
}

@test "a failing migration stops the run and is not marked" {
  migration 1000000031 'false'
  migration 1000000032
  run "$GATE"
  [ "$status" -ne 0 ]
  ran 1000000031
  not_marked 1000000031
  not_ran 1000000032
}

@test "killing the gate mid-run leaves the interrupted migration unmarked" {
  migration 1000000041 'sleep 3'
  migration 1000000042 'sudo true'
  run timeout -s TERM 1 "$GATE"
  [ "$status" -eq 124 ]
  not_marked 1000000041
  not_marked 1000000042
}

@test "migrations see the real OMARCHY_PATH" {
  migration 1000000051 'ln -sfn "$OMARCHY_PATH/default" "$HOME/default-link"'
  run "$GATE"
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/default-link")" = "$OMARCHY_PATH/default" ]
}

@test "a held migration is logged once across runs" {
  migration 1000000061 'sudo true'
  "$GATE"
  "$GATE"
  [ "$(grep -c 'held 1000000061.sh' "$HOME/.local/state/cachyos-quattro/held.log")" -eq 1 ]
}

@test "one desktop notification is sent when migrations are held and a session bus exists" {
  migration 1000000071 'sudo true'
  migration 1000000072 'pkexec true'
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\necho "$*" >>"$HOME/notify.log"\n' >"$BATS_TEST_TMPDIR/bin/notify-send"
  chmod +x "$BATS_TEST_TMPDIR/bin/notify-send"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent run "$GATE"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$HOME/notify.log")" -eq 1 ]
  grep -q '2' "$HOME/notify.log"
}

@test "a missing ledger runs nothing" {
  migration 1000000081
  rm "$SHARE/ledger/migrations.tsv"
  run "$GATE"
  [ "$status" -eq 1 ]
  [[ $output == *"cannot read"* ]]
  [ ! -e "$HOME/ran.log" ]
}

@test "without an Omarchy bin directory every unreviewed migration is held" {
  rm -r "${OMARCHY_PATH:?}/bin"
  migration 1000000091 'omarchy-whatever'
  run "$GATE" --status
  grep -qE '^1000000091\.sh	held	' <<<"$output"
}
