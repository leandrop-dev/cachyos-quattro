#!/usr/bin/env bats

LEDGER="$BATS_TEST_DIRNAME/../../ledger"

rows() {
  grep -v '^#' "$1"
}

@test "files.tsv has exact paths, known verdicts and no duplicates" {
  run bash -c "grep -v '^#' '$LEDGER/files.tsv' | cut -f1 | grep -E '[*?[]'"
  [ "$status" -eq 1 ]
  run bash -c "grep -v '^#' '$LEDGER/files.tsv' | cut -f2 | grep -vxE 'noextract|allow|restore'"
  [ "$status" -eq 1 ]
  [ -z "$(rows "$LEDGER/files.tsv" | cut -f1 | sort | uniq -d)" ]
}

@test "files.tsv covers every shipped 4.0.6 file outside /etc/skel" {
  shipped=$(awk -F'\t' '$1 !~ /^etc\/skel\// {print $1}' "$LEDGER/files.4.0.6.tsv" | sort)
  reviewed=$(rows "$LEDGER/files.tsv" | awk -F'\t' '$2 != "restore" {print $1}' | sort)
  [ "$shipped" = "$reviewed" ]
}

@test "the files that break CachyOS boot are noextract" {
  for path in etc/mkinitcpio.conf.d/omarchy_hooks.conf \
    etc/limine-entry-tool.d/omarchy-defaults.conf \
    etc/limine-entry-tool.d/omarchy-uki.conf; do
    rows "$LEDGER/files.tsv" | grep -qxE "$path	noextract	.*"
  done
}

@test "migrations.tsv matches the 4.0.6 migrations by name and sha256" {
  generated=$(cut -f1,2 "$LEDGER/migrations.4.0.6.tsv" | sort)
  reviewed=$(rows "$LEDGER/migrations.tsv" | cut -f1,2 | sort)
  [ "$generated" = "$reviewed" ]
}

@test "every migration verdict is known" {
  run bash -c "grep -v '^#' '$LEDGER/migrations.tsv' | cut -f3 | grep -vxE 'run|skip|replace|preseed'"
  [ "$status" -eq 1 ]
}

@test "install-steps.tsv skips the steps that rewrite pacman, snapper and NVIDIA setup" {
  for step in config/snapper.sh hardware/nvidia.sh hardware/pacman.sh post-install/pacman.sh; do
    rows "$LEDGER/install-steps.tsv" | grep -qxE "$step	skip	.*"
  done
}

@test "boot-critical overlapping packages come from CachyOS" {
  for pkg in limine-mkinitcpio-hook limine-snapper-sync; do
    rows "$LEDGER/repo-overlap.tsv" | awk -F'\t' -v p="$pkg" '$1 == p && $4 == "cachyos" {found = 1} END {exit !found}'
  done
}

@test "releases.tsv records 4.0.6 as reviewed" {
  rows "$LEDGER/releases.tsv" | grep -qxE '4\.0\.6	[0-9-]+	reviewed'
}
