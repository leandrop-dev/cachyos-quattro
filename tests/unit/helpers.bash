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
