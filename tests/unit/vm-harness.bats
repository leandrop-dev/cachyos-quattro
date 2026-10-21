#!/usr/bin/env bats

load helpers

VM="$BATS_TEST_DIRNAME/../vm"

load_vm_lib() {
  # shellcheck source=tests/vm/lib.sh
  source "$VM/lib.sh"
}

@test "vm_qcodes maps the LUKS passphrase to QMP qcodes" {
  load_vm_lib
  run vm_qcodes cq-test-1
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' c q minus t e s t minus 1)" ]
}

@test "vm_qcodes refuses characters it cannot type" {
  load_vm_lib
  run vm_qcodes 'Abc'
  [ "$status" -eq 2 ]
  [[ $output == *"unsupported character 'A'"* ]]
}

@test "vm_is_luks follows the image name" {
  load_vm_lib
  vm_is_luks limine-luks
  run vm_is_luks limine-plain
  [ "$status" -eq 1 ]
}

@test "run.sh refuses an unknown scenario" {
  run "$VM/run.sh" limine-plain no-such-scenario
  [ "$status" -eq 2 ]
  [[ $output == *"no scenario"* ]]
}

@test "run.sh refuses a missing golden image" {
  run "$VM/run.sh" no-such-image smoke
  [ "$status" -eq 2 ]
  [[ $output == *"no golden image"* ]]
}

@test "golden.sh install refuses a missing ISO" {
  run "$VM/golden.sh" install test-image "$BATS_TEST_TMPDIR/missing.iso"
  [ "$status" -eq 2 ]
  [[ $output == *"ISO not found"* ]]
}
