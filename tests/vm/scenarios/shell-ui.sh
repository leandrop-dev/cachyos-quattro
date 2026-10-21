#!/bin/bash
# Runs on the guest: install; the harness reboots, then shell-ui.host.sh drives the Omarchy
# session from the host (menu colours, lock and unlock twice).

set -euo pipefail
bash tests/vm/guest/install-omarchy.sh || {
  echo "shell-ui: install failed" >&2
  exit 1
}
echo "shell-ui: installed"
