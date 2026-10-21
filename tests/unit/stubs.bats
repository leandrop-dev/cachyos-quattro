#!/usr/bin/env bats

load helpers

PACKAGE="$BATS_TEST_DIRNAME/../../package"
LEDGER="$BATS_TEST_DIRNAME/../../ledger"

# stubbed: the stubbed command names; fails when the list is missing or empty.
stubbed() {
  grep -v '^#' "$PACKAGE/stubbed-commands.txt" | grep .
}

# Link each stubbed name to the stub, the way the package installs them in /usr/local/bin.
link_stubs() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  while read -r name; do
    ln -s "$PACKAGE/libexec/stub" "$BATS_TEST_TMPDIR/bin/$name"
  done <<<"$(stubbed)"
}

# fake_real <name>: a stand-in for /usr/bin/<name> under CQ_ROOT that echoes its arguments.
fake_real() {
  mkdir -p "$CQ_ROOT/usr/bin"
  printf '#!/bin/bash\necho "real %s $*"\n' "$1" >"$CQ_ROOT/usr/bin/$1"
  chmod +x "$CQ_ROOT/usr/bin/$1"
}

@test "every stubbed command exits 1 with its own explanation" {
  stubbed >/dev/null
  link_stubs
  while read -r name; do
    label=$name
    [[ $name != omarchy-snapshot ]] || label="$name restore"
    run "$BATS_TEST_TMPDIR/bin/$name" restore
    [ "$status" -eq 1 ] || { echo "$name exited $status"; false; }
    [[ $output == *"$label is blocked on CachyOS: "* ]] || { echo "$name: $output"; false; }
    [[ $output != *"no explanation recorded"* ]] || { echo "$name has no case entry"; false; }
  done <<<"$(stubbed)"
}

@test "CQ_ALLOW_DANGEROUS=1 runs the real command with its arguments" {
  link_stubs
  fake_real omarchy-refresh-limine
  CQ_ALLOW_DANGEROUS=1 run "$BATS_TEST_TMPDIR/bin/omarchy-refresh-limine" --yes two
  [ "$status" -eq 0 ]
  [ "$output" = "real omarchy-refresh-limine --yes two" ]
}

@test "omarchy-snapshot create passes through to the real command" {
  link_stubs
  fake_real omarchy-snapshot
  run "$BATS_TEST_TMPDIR/bin/omarchy-snapshot" create
  [ "$status" -eq 0 ]
  [ "$output" = "real omarchy-snapshot create" ]
}

@test "omarchy-snapshot restore is refused unless CQ_ALLOW_DANGEROUS=1" {
  link_stubs
  fake_real omarchy-snapshot
  run "$BATS_TEST_TMPDIR/bin/omarchy-snapshot" restore
  [ "$status" -eq 1 ]
  [[ $output == *"omarchy-snapshot restore is blocked on CachyOS: "* ]]
  CQ_ALLOW_DANGEROUS=1 run "$BATS_TEST_TMPDIR/bin/omarchy-snapshot" restore
  [ "$status" -eq 0 ]
  [ "$output" = "real omarchy-snapshot restore" ]
}

@test "every stubbed command exists in the reviewed Omarchy release" {
  stubbed >/dev/null
  while read -r name; do
    cut -f1 "$LEDGER/commands.$(reviewed_release).tsv" | grep -qxF "$name" || { echo "$name is not an Omarchy $(reviewed_release) command"; false; }
  done <<<"$(stubbed)"
}
