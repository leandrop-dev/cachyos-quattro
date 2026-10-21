#!/usr/bin/env bats

load helpers

GEN="$BATS_TEST_DIRNAME/../../tools/gen-noextract"
LEDGER="$BATS_TEST_DIRNAME/../../ledger"

@test "the drop-in lists exactly the noextract rows of files.tsv" {
  run "$GEN" "$LEDGER/files.tsv"
  [ "$status" -eq 0 ]
  expected=$(awk -F'\t' '!/^#/ && $2 == "noextract" {print "NoExtract = " $1}' "$LEDGER/files.tsv")
  [ "$(grep -v '^#' <<<"$output")" = "$expected" ]
  [ "$(grep -c '^NoExtract = ' <<<"$output")" -eq 11 ]
}

@test "the drop-in has no globs or leading slashes" {
  run "$GEN" "$LEDGER/files.tsv"
  [ "$status" -eq 0 ]
  run grep -E '^NoExtract = ([^ ]*[*?[]|[/!])' <<<"$output"
  [ "$status" -eq 1 ]
}

@test "gen-noextract refuses a glob in a noextract row" {
  printf 'etc/mkinitcpio.conf.d/*\tnoextract\tglob\n' >"$BATS_TEST_TMPDIR/files.tsv"
  run "$GEN" "$BATS_TEST_TMPDIR/files.tsv"
  [ "$status" -ne 0 ]
  [[ $output == *"not an exact path"* ]]
}

@test "pacman-conf reads every entry through an Include in [options]" {
  "$GEN" "$LEDGER/files.tsv" >"$BATS_TEST_TMPDIR/cachyos-quattro.conf"
  printf '[options]\nInclude = %s\n' "$BATS_TEST_TMPDIR/cachyos-quattro.conf" >"$BATS_TEST_TMPDIR/pacman.conf"
  run pacman-conf --config "$BATS_TEST_TMPDIR/pacman.conf" NoExtract
  [ "$status" -eq 0 ]
  [ "$output" = "$(awk -F'\t' '!/^#/ && $2 == "noextract" {print $1}' "$LEDGER/files.tsv")" ]
}
