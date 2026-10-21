#!/bin/bash
# Runs on the guest. Passes on an unmodified CachyOS image.

set -euo pipefail

grep -qx 'ID=cachyos' /etc/os-release || {
  echo "smoke: /etc/os-release does not say ID=cachyos" >&2
  exit 1
}

state=$(systemctl is-system-running --wait || true)
case $state in
  running | degraded) echo "smoke: system $state" ;;
  *)
    echo "smoke: system state is '$state'" >&2
    exit 1
    ;;
esac
