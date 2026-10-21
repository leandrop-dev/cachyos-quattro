#!/bin/bash
# Create and prepare golden CachyOS images. See docs/testing.md § "Golden images".
#
#   golden.sh install <name> <iso>   new disk, boot the ISO in a window (Calamares)
#   golden.sh boot <name>            boot the installed disk in a window, SSH on 127.0.0.1:2222
#   golden.sh seal <name>            make the image read-only and record its checksum

set -euo pipefail
# shellcheck source=tests/vm/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

(($# >= 2)) || usage
cmd=$1 name=$2
disk="$IMAGES_DIR/$name.qcow2"
vars="$IMAGES_DIR/$name.vars.fd"
mkdir -p "$IMAGES_DIR"

case $cmd in
  install)
    iso=${3:?golden.sh install <name> <iso>}
    [[ -f $iso ]] || vm_die "ISO not found: $iso"
    [[ ! -e $disk ]] || vm_die "$disk already exists; delete it to start over"
    qemu-img create -q -f qcow2 "$disk" 40G
    cp "$OVMF_VARS" "$vars"
    [[ -f $SSH_KEY ]] || ssh-keygen -q -t ed25519 -N '' -C cachyos-quattro-harness -f "$SSH_KEY"
    mapfile -t args < <(vm_qemu_args "$disk" "$vars" 2222)
    exec qemu-system-x86_64 "${args[@]}" -cdrom "$iso" -boot menu=on -vga virtio -display gtk
    ;;
  boot)
    [[ -f $disk ]] || vm_die "no image $disk; run 'golden.sh install' first"
    [[ -w $disk ]] || vm_die "$disk is sealed (read-only)"
    mapfile -t args < <(vm_qemu_args "$disk" "$vars" 2222)
    exec qemu-system-x86_64 "${args[@]}" -vga virtio -display gtk
    ;;
  seal)
    [[ -f $disk ]] || vm_die "no image $disk"
    chmod a-w "$disk" "$vars"
    {
      echo "sealed=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "sha256=$(sha256sum "$disk" | cut -d' ' -f1)"
    } >"$IMAGES_DIR/$name.info"
    cat "$IMAGES_DIR/$name.info"
    ;;
  *)
    usage
    ;;
esac
