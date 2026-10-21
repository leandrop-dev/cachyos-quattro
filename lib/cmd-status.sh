# shellcheck shell=bash
# cachyos-quattro status: run every protection check, then show Omarchy's state.
# Sourced by bin/cachyos-quattro (task 09); cmd_status returns 1 when a check fails.

cmd_status() {
  local rc=0 held
  sudo "${CQ_ROOT:-}/usr/lib/cachyos-quattro/verify" || rc=1

  echo
  echo "Omarchy packages:"
  pacman -Q | grep -E '^omarchy(-settings)? ' || echo "  not installed"

  echo
  held=$(omarchy-migrate --status | awk -F'\t' '$2 == "held" { printf "  %s  %s\n", $1, $3 }')
  if [[ -n $held ]]; then
    echo "Held Omarchy migrations (not run, still pending until reviewed in the ledger):"
    echo "$held"
  else
    echo "Held Omarchy migrations: none"
  fi

  echo
  echo "Note: 'pacman -Qkk omarchy-settings' reports Omarchy's blocked boot and tuning files"
  echo "as missing. That is NoExtract working as intended."
  return "$rc"
}
