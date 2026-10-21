#!/bin/bash
# Runs on the host after shell-ui.sh and the reboot (run.sh sets VM_QMP, VM_PORT, VM_IMAGE and
# VM_SHOTS). Logs in at SDDM on unencrypted images (LUKS images log in automatically), then
# checks the Omarchy shell: the menu is drawn in colour rather than black (the Qt 6.12 palette
# report, task 16), and the screen locks and unlocks twice (the quickshell 0.3.2 lock report).

set -euo pipefail
# shellcheck source=tests/vm/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Expanded on the guest, not here.
# shellcheck disable=SC2016
session='. /usr/share/omarchy/default/bash/env-bootstrap; export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1; export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -n1)'
guest() { vm_ssh "$VM_PORT" "bash -s" <<<"$session; $1"; }
shot() { vm_screendump "$VM_QMP" "$VM_SHOTS/$1.png" || vm_die "screendump $1 failed"; }
# mean <png> [crop]: average brightness from 0 to 1, of the whole image or a WxH+X+Y region.
mean() { magick "$1" ${2:+-crop "$2"} -colorspace Gray -format '%[fx:mean]' info:; }
locked() { guest 'omarchy-hyprland-session-locked'; }

if ! vm_is_luks "$VM_IMAGE"; then
  sleep 15
  vm_log "logging in at SDDM"
  vm_type "$VM_QMP" "$VM_PASSWORD"
fi
for _ in {1..30}; do
  vm_ssh "$VM_PORT" 'pgrep -u tester -x Hyprland >/dev/null && pgrep -u tester -x quickshell >/dev/null' && break
  sleep 3
done
vm_ssh "$VM_PORT" 'pgrep -u tester -x quickshell >/dev/null' || vm_die "no Omarchy session"
sleep 20
shot desktop

guest 'omarchy-menu summon'
sleep 3
shot menu
menu=$(mean "$VM_SHOTS/menu.png" 300x500+490+150)
vm_log "menu brightness $menu"
awk -v m="$menu" 'BEGIN { exit !(m > 0.05) }' || vm_die "the menu is drawn black (brightness $menu)"
guest 'omarchy-menu close'

for round in 1 2; do
  guest 'omarchy-system-lock'
  sleep 5
  locked || vm_die "the screen did not lock (round $round)"
  shot "locked-$round"
  vm_type "$VM_QMP" "$VM_PASSWORD"
  sleep 5
  if locked; then
    shot "still-locked-$round"
    vm_die "the screen did not unlock (round $round)"
  fi
  shot "unlocked-$round"
  vm_log "locked and unlocked (round $round)"
done
vm_log "shell-ui: ok (screendumps in $VM_SHOTS)"
