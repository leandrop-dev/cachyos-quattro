#!/bin/bash
# Run one scenario on a disposable overlay of a sealed golden image.
#
#   run.sh <image> <scenario>
#
# Copies the working tree to ~/cq on the guest, runs tests/vm/scenarios/<scenario>.sh
# there, reboots (typing the LUKS passphrase on *-luks* images), then runs
# <scenario>.after-reboot.sh if it exists, or scenarios/smoke.sh otherwise, and finally
# <scenario>.host.sh on the host, if it exists, with VM_QMP, VM_PORT, VM_IMAGE and VM_SHOTS
# (a directory for screendumps) set.
# KEEP=1 keeps the overlay even when the run passes.

set -euo pipefail
# shellcheck source=tests/vm/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

(($# == 2)) || vm_die "usage: run.sh <image> <scenario>"
image=$1 scenario=$2
golden="$IMAGES_DIR/$image.qcow2"
script="$VM_DIR/scenarios/$scenario.sh"
after="$VM_DIR/scenarios/$scenario.after-reboot.sh"
[[ -f $script ]] || vm_die "no scenario $script"

passed=0
trap 'vm_overlay_cleanup "$passed"' EXIT
vm_overlay_boot "$image" "$scenario"

vm_log "copying working tree to ~/cq"
tar -C "$REPO_DIR" -c --exclude=./.git --exclude=./build --exclude=./tests/vm/images --exclude=./tests/vm/run . |
  vm_ssh "$port" 'rm -rf ~/cq && mkdir -p ~/cq && tar -x -C ~/cq'

vm_log "running scenario $scenario"
vm_ssh "$port" "cd ~/cq && bash tests/vm/scenarios/$scenario.sh" || vm_die "scenario $scenario failed"

vm_log "rebooting"
boot_before=$(vm_ssh "$port" 'cat /proc/sys/kernel/random/boot_id')
vm_ssh "$port" 'sudo systemctl reboot' || true
sleep 10
vm_unlock_and_wait "$qmp" "$port" "$image" || vm_die "guest did not come back after reboot"
boot_after=$(vm_ssh "$port" 'cat /proc/sys/kernel/random/boot_id')
[[ $boot_after != "$boot_before" ]] || vm_die "boot id unchanged; the guest did not reboot"
vm_log "rebooted (boot id $boot_after)"

if [[ -f $after ]]; then
  vm_ssh "$port" "cd ~/cq && bash tests/vm/scenarios/$scenario.after-reboot.sh" ||
    vm_die "after-reboot check for $scenario failed"
else
  vm_ssh "$port" "cd ~/cq && bash tests/vm/scenarios/smoke.sh" || vm_die "post-reboot smoke check failed"
fi

host=$VM_DIR/scenarios/$scenario.host.sh
if [[ -f $host ]]; then
  vm_log "running host checks for $scenario"
  mkdir -p "$RUN_DIR/$run_id-shots"
  VM_QMP=$qmp VM_PORT=$port VM_IMAGE=$image VM_SHOTS=$RUN_DIR/$run_id-shots bash "$host" ||
    vm_die "host check for $scenario failed"
fi

passed=1
vm_log "PASS $image $scenario"
