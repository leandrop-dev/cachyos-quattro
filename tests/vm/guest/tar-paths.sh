#!/bin/bash
# Runs on the guest via `bash -s -- <path>...` (fetch.sh). Writes a tar stream of
# the paths that exist to stdout, read as root; reports missing paths on stderr.

set -euo pipefail

rel=()
for p in "$@"; do
  if sudo test -e "$p"; then
    rel+=("${p#/}")
  else
    echo "fetch: missing $p" >&2
  fi
done
((${#rel[@]})) || exit 0
sudo tar -C / -cf - "${rel[@]}"
