# Shared setup for bats tests. Runtime scripts read paths through CQ_ROOT,
# so each test gets its own fake root populated from tests/fixtures/.

FIXTURES_DIR="$BATS_TEST_DIRNAME/../fixtures"

setup() {
  export CQ_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$CQ_ROOT"
}

# mkroot <fixture>: copy tests/fixtures/<fixture>/ into $CQ_ROOT.
mkroot() {
  local fixture="$FIXTURES_DIR/$1"
  [[ -d $fixture ]] || {
    echo "mkroot: no fixture named '$1' in $FIXTURES_DIR" >&2
    return 1
  }
  cp -a "$fixture/." "$CQ_ROOT/"
}

# reviewed_release: the last Omarchy release reviewed in ledger/releases.tsv. The generated
# ledger files (files.<v>.tsv, migrations.<v>.tsv, commands.<v>.tsv) are named after it.
reviewed_release() {
  awk -F'\t' '!/^#/ && $3 == "reviewed" { v = $1 } END { print v }' "$BATS_TEST_DIRNAME/../../ledger/releases.tsv"
}
