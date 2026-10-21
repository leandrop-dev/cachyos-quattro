#!/bin/bash
# Copy files out of a sealed golden image without changing it.
#
#   fetch.sh <image> <outdir> <guest-path>...
#
# Boots a disposable overlay, reads the paths as root (missing ones are listed and
# skipped), and unpacks them under <outdir> with their guest paths. Also writes
# <outdir>/proc/cmdline and <outdir>/pacman-Qqe.txt.

set -euo pipefail
# shellcheck source=tests/vm/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

(($# >= 3)) || vm_die "usage: fetch.sh <image> <outdir> <guest-path>..."
image=$1 outdir=$2
shift 2

passed=0
trap 'vm_overlay_cleanup "$passed"' EXIT
vm_overlay_boot "$image" fetch

mkdir -p "$outdir/proc"
vm_ssh "$port" 'cat /proc/cmdline' >"$outdir/proc/cmdline"
vm_ssh "$port" 'pacman -Qqe' >"$outdir/pacman-Qqe.txt"
vm_ssh "$port" "bash -s -- $(printf '%q ' "$@")" <"$VM_DIR/guest/tar-paths.sh" | tar -C "$outdir" -xf -

passed=1
vm_log "fetched into $outdir"
