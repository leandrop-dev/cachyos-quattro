# shellcheck shell=bash
# cachyos-quattro update [omarchy-update options]: bring the protections up to date with this
# checkout, check them, run Omarchy's own update, and check again.

# shellcheck source=lib/cmd-install.sh
source "$CQ_REPO/lib/cmd-install.sh"

CQ_REVIEW_ISSUES='https://github.com/leandrop-dev/cachyos-quattro/issues?q=label:upstream-release'

# cq_guard_outdated: true, listing the differences, when the installed cachyos-quattro package
# differs from what this checkout would build; false when it matches.
cq_guard_outdated() {
  local f name diffs=()
  for f in "$CQ_REPO"/ledger/*.tsv; do
    cmp -s "$f" "$(cq_root "/usr/share/cachyos-quattro/ledger/${f##*/}")" || diffs+=("ledger/${f##*/}")
  done
  for f in "$CQ_REPO"/package/libexec/*; do
    cmp -s "$f" "$(cq_root "/usr/lib/cachyos-quattro/${f##*/}")" || diffs+=("libexec/${f##*/}")
  done
  for f in "$CQ_REPO"/package/hooks/*.hook; do
    cmp -s "$f" "$(cq_root "/usr/share/libalpm/hooks/${f##*/}")" || diffs+=("hooks/${f##*/}")
  done
  while read -r name; do
    [[ -L $(cq_root "/usr/local/bin/$name") ]] || diffs+=("stub $name")
  done < <(grep -v '^#' "$CQ_REPO/package/stubbed-commands.txt")
  cmp -s <("$CQ_REPO/tools/gen-noextract" "$CQ_REPO/ledger/files.tsv") "$(cq_root /etc/pacman.d/cachyos-quattro.conf)" ||
    diffs+=("/etc/pacman.d/cachyos-quattro.conf")
  ((${#diffs[@]})) || return 1
  printf 'differs from this checkout: %s\n' "${diffs[@]}"
}

cmd_update() {
  local verify held rc=0
  verify=$(cq_root /usr/lib/cachyos-quattro/verify)
  [[ -e $(cq_lib_dir)/installed ]] || cq_die "cachyos-quattro is not installed; run 'cachyos-quattro install'"
  sudo true || cq_die "update needs sudo"

  if [[ -d $CQ_REPO/.git ]]; then
    cq_log "== updating $CQ_REPO"
    git -C "$CQ_REPO" pull --ff-only || cq_die "could not fast-forward $CQ_REPO; resolve it and run update again"
  fi
  # A new ledger must be installed before Omarchy's packages, so the transaction check and
  # the migration gate know the new release.
  if cq_guard_outdated; then
    cq_log "== rebuilding the cachyos-quattro package"
    cq_run_phase cq_install_phase_guard
    ((CQ_PHASE_RC == 0)) || cq_die "could not rebuild the cachyos-quattro package"
  fi

  cq_log "== checking the protections before the update"
  sudo "$verify" || cq_die "a protection check failed; fix it before updating"
  cq_install_post_update_hook

  cq_log "== omarchy-update"
  # Omarchy's scripts expect OMARCHY_PATH, which its login profile sets; this may run without it.
  OMARCHY_PATH=${OMARCHY_PATH:-$CQ_OMARCHY_PATH} omarchy-update "$@" || cq_die "omarchy-update failed; see its output above"

  cq_log "== checking the protections after the update"
  sudo "$verify" || rc=1
  held=$(omarchy-migrate --status | awk -F'\t' '$2 == "held" { printf "  %s  %s\n", $1, $3 }')
  if [[ -n $held ]]; then
    cq_log "Held Omarchy migrations (not run until reviewed in the ledger):"
    cq_log "$held"
    cq_log "Reviews of new Omarchy releases: $CQ_REVIEW_ISSUES"
  fi
  return "$rc"
}
