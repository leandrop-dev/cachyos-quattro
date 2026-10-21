#!/usr/bin/env bats

load helpers

TXN_CHECK="$BATS_TEST_DIRNAME/../../package/libexec/txn-check"
LEDGER="$BATS_TEST_DIRNAME/../../ledger"

setup() {
  export CQ_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$CQ_ROOT/usr/share/cachyos-quattro/ledger" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/cache"
  cp "$LEDGER/files.tsv" "$CQ_ROOT/usr/share/cachyos-quattro/ledger/"

  # Fake sync databases: "repo name filename" per line, in pacman.conf order.
  export FAKE_SYNC="$BATS_TEST_TMPDIR/sync.txt"
  export FAKE_CACHE="$BATS_TEST_TMPDIR/cache"
  export FAKE_CALLS="$BATS_TEST_TMPDIR/pacman-calls"
  cat >"$FAKE_SYNC" <<'EOF'
cachyos mkinitcpio mkinitcpio-40-1-any.pkg.tar.zst
cachyos limine-mkinitcpio-hook limine-mkinitcpio-hook-1.40.0-1-any.pkg.tar.zst
omarchy limine-mkinitcpio-hook limine-mkinitcpio-hook-1.40.0-2-any.pkg.tar.zst
omarchy omarchy-settings omarchy-settings-9.9.9-1-any.pkg.tar.zst
EOF

  cat >"$BATS_TEST_TMPDIR/bin/pacman" <<'EOF'
#!/bin/bash
# Fake pacman: answers the queries txn-check makes from $FAKE_SYNC.
echo "pacman $*" >>"$FAKE_CALLS"
case $1 in
-Slq)
  awk -v r="${2:-}" 'r == "" || $1 == r {print $2}' "$FAKE_SYNC"
  ;;
-Sp)
  for arg in "$@"; do
    [[ $arg == -* || $arg == *%* ]] && continue
    line=$(awk -v n="$arg" '$2 == n {print $1 "|" $2 "|" $3; exit}' "$FAKE_SYNC")
    [[ -n $line ]] || { echo "error: target not found: $arg" >&2; exit 1; }
    echo "$line"
  done
  ;;
*)
  echo "fake pacman: unexpected $*" >&2
  exit 2
  ;;
esac
EOF
  cat >"$BATS_TEST_TMPDIR/bin/pacman-conf" <<'EOF'
#!/bin/bash
case $1 in
--repo-list) awk '!seen[$1]++ {print $1}' "$FAKE_SYNC" ;;
CacheDir) echo "$FAKE_CACHE/" ;;
*) echo "fake pacman-conf: unexpected $*" >&2; exit 2 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/pacman" "$BATS_TEST_TMPDIR/bin/pacman-conf"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CQ_PACMAN_CMDLINE="pacman -Syu"
}

# cache_pkg <filename> <path>...: a package file in the fake cache shipping <path>s.
cache_pkg() {
  local file=$1 tree="$BATS_TEST_TMPDIR/tree-$1"
  shift
  mkdir -p "$tree"
  for path in "$@"; do
    mkdir -p "$tree/$(dirname "$path")"
    echo "# $path" >"$tree/$path"
  done
  printf 'pkgname = fake\n' >"$tree/.PKGINFO"
  (cd "$tree" && bsdtar --zstd -cf "$FAKE_CACHE/$file" .PKGINFO "${@%%/*}")
}

@test "a path the ledger reviewed passes" {
  cache_pkg omarchy-settings-9.9.9-1-any.pkg.tar.zst etc/mkinitcpio.conf.d/omarchy_hooks.conf
  run "$TXN_CHECK" <<<$'omarchy-settings\netc/mkinitcpio.conf.d/\netc/mkinitcpio.conf.d/omarchy_hooks.conf'
  [ "$status" -eq 0 ]
}

@test "a new Omarchy drop-in aborts the transaction" {
  cache_pkg omarchy-settings-9.9.9-1-any.pkg.tar.zst etc/mkinitcpio.conf.d/omarchy_new.conf
  run "$TXN_CHECK" <<<$'omarchy-settings\netc/mkinitcpio.conf.d/omarchy_new.conf'
  [ "$status" -eq 1 ]
  [[ $output == *"unreviewed Omarchy file etc/mkinitcpio.conf.d/omarchy_new.conf (package omarchy-settings)"* ]]
  [[ $output == *"CQ_TXN_ALLOW=1"* ]]
}

@test "a renamed Omarchy drop-in aborts the transaction" {
  cache_pkg omarchy-settings-9.9.9-1-any.pkg.tar.zst etc/mkinitcpio.conf.d/omarchy_hooks2.conf
  run "$TXN_CHECK" <<<$'omarchy-settings\netc/mkinitcpio.conf.d/omarchy_hooks2.conf'
  [ "$status" -eq 1 ]
  [[ $output == *"unreviewed Omarchy file etc/mkinitcpio.conf.d/omarchy_hooks2.conf"* ]]
}

@test "paths from CachyOS packages pass" {
  run "$TXN_CHECK" <<<$'mkinitcpio\netc/mkinitcpio.conf.d/cachyos.conf'
  [ "$status" -eq 0 ]
}

@test "a package in both repos that CachyOS wins is not inspected" {
  run "$TXN_CHECK" <<<$'limine-mkinitcpio-hook\netc/mkinitcpio.conf.d/limine.conf'
  [ "$status" -eq 0 ]
}

@test "an Omarchy package missing from the cache fails closed" {
  run "$TXN_CHECK" <<<$'omarchy-settings\netc/mkinitcpio.conf.d/omarchy_hooks.conf'
  [ "$status" -eq 1 ]
  [[ $output == *"omarchy-settings-9.9.9-1-any.pkg.tar.zst is not in pacman's cache"* ]]
}

@test "an Omarchy package installed with pacman -U fails closed" {
  cache_pkg omarchy-settings-9.9.9-1-any.pkg.tar.zst etc/mkinitcpio.conf.d/omarchy_hooks.conf
  CQ_PACMAN_CMDLINE="pacman -U /tmp/omarchy-settings.pkg.tar.zst" run "$TXN_CHECK" <<<$'omarchy-settings\netc/mkinitcpio.conf.d/omarchy_hooks.conf'
  [ "$status" -eq 1 ]
  [[ $output == *"omarchy-settings is installed from a file"* ]]
}

@test "an omarchy package that no repository has fails closed" {
  run "$TXN_CHECK" <<<$'omarchy-extra\netc/sysctl.d/99-extra.conf'
  [ "$status" -eq 1 ]
  [[ $output == *"omarchy-extra is not in any repository"* ]]
}

@test "CQ_TXN_ALLOW=1 lets an unreviewed file through with a warning" {
  cache_pkg omarchy-settings-9.9.9-1-any.pkg.tar.zst etc/mkinitcpio.conf.d/omarchy_new.conf
  CQ_TXN_ALLOW=1 run "$TXN_CHECK" <<<$'omarchy-settings\netc/mkinitcpio.conf.d/omarchy_new.conf'
  [ "$status" -eq 0 ]
  [[ $output == *"unreviewed Omarchy file etc/mkinitcpio.conf.d/omarchy_new.conf"* ]]
  [[ $output == *"warning: CQ_TXN_ALLOW=1"* ]]
}

@test "a transaction without boot-sensitive paths does not query pacman" {
  run "$TXN_CHECK" <<<$'omarchy-settings\nfirefox'
  [ "$status" -eq 0 ]
  [ ! -e "$FAKE_CALLS" ]
}

@test "a missing ledger fails closed" {
  rm "$CQ_ROOT/usr/share/cachyos-quattro/ledger/files.tsv"
  run "$TXN_CHECK" <<<$'mkinitcpio\netc/mkinitcpio.conf.d/cachyos.conf'
  [ "$status" -eq 1 ]
  [[ $output == *"cannot read the ledger"* ]]
}

@test "a pacman query failure fails closed" {
  printf '#!/bin/bash\necho "error: failed to init transaction" >&2\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/pacman"
  run "$TXN_CHECK" <<<$'omarchy-settings\netc/mkinitcpio.conf.d/omarchy_hooks.conf'
  [ "$status" -eq 1 ]
  [[ $output == *"failed to init transaction"* ]]
}

@test "every Omarchy 4.0.6 file under a hook target path is in the ledger" {
  hook="$BATS_TEST_DIRNAME/../../package/hooks/04-cachyos-quattro-txn-check.hook"
  targets=$(sed -n '/^Type = Path$/,/^\[Action\]$/s/^Target = //p' "$hook")
  [ -n "$targets" ]
  reviewed=$(grep -v '^#' "$LEDGER/files.tsv" | cut -f1)
  while read -r path; do
    while read -r pattern; do
      # alpm matches Target with fnmatch and no FNM_PATHNAME, so * also matches /.
      # shellcheck disable=SC2053
      [[ $path == $pattern ]] || continue
      grep -qxF -e "$path" <<<"$reviewed" || { echo "unreviewed: $path"; false; }
    done <<<"$targets"
  done < <(cut -f1 "$LEDGER/files.4.0.6.tsv")
}
