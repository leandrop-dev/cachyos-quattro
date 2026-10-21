#!/usr/bin/env bats

# Single-quoted $arch is pacman's own variable.
# shellcheck disable=SC2016

load helpers

setup() {
  export CQ_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$CQ_ROOT"
  # shellcheck source=lib/pacman-conf.sh
  source "$BATS_TEST_DIRNAME/../../lib/pacman-conf.sh"
  mkroot cachyos-limine-luks
  CONF=$CQ_ROOT/etc/pacman.conf
  OUT=$BATS_TEST_TMPDIR/pacman.conf
}

# A copy that pacman-conf can parse here: every /etc/pacman.d path points into CQ_ROOT,
# and the drop-in exists with one NoExtract entry.
parseable() {
  printf 'NoExtract = etc/mkinitcpio.conf.d/omarchy_hooks.conf\n' >"$CQ_ROOT/etc/pacman.d/cachyos-quattro.conf"
  sed "s|/etc/pacman.d/|$CQ_ROOT/etc/pacman.d/|" "$1" >"$BATS_TEST_TMPDIR/parseable.conf"
  echo "$BATS_TEST_TMPDIR/parseable.conf"
}

@test "the Include goes inside [options] and [omarchy] becomes the last repository" {
  cq_pacman_conf_add "$CONF" "$OUT"
  conf=$(parseable "$OUT")
  [ "$(pacman-conf --config "$conf" --repo-list | tail -n1)" = omarchy ]
  [ "$(pacman-conf --config "$conf" NoExtract)" = etc/mkinitcpio.conf.d/omarchy_hooks.conf ]
  [ "$(pacman-conf --config "$conf" --repo omarchy Server)" = 'https://pkgs.omarchy.org/stable/x86_64' ]
  grep -A1 -x '\[options\]' "$OUT" | grep -qx '# BEGIN cachyos-quattro'
}

@test "every existing line is kept, in order" {
  cq_pacman_conf_add "$CONF" "$OUT"
  [ "$(grep -vxF -f <(cq_pacman_conf_blocks) "$OUT")" = "$(cat "$CONF")" ]
}

@test "adding twice changes nothing the second time" {
  cq_pacman_conf_add "$CONF" "$OUT"
  cq_pacman_conf_add "$OUT" "$BATS_TEST_TMPDIR/twice.conf"
  cmp "$OUT" "$BATS_TEST_TMPDIR/twice.conf"
}

@test "removing the marked blocks restores the original file exactly" {
  cq_pacman_conf_add "$CONF" "$OUT"
  cq_pacman_conf_remove "$OUT" "$BATS_TEST_TMPDIR/removed.conf"
  cmp "$CONF" "$BATS_TEST_TMPDIR/removed.conf"
}

@test "a pacman.conf without [options] is refused" {
  sed -i '/^\[options\]$/d' "$CONF"
  run cq_pacman_conf_add "$CONF" "$OUT"
  [ "$status" -eq 1 ]
  [[ $output == *"no [options] section"* ]]
}

@test "a pacman.conf that already has an [omarchy] repository is refused" {
  printf '\n[omarchy]\nServer = https://pkgs.omarchy.org/stable/$arch\n' >>"$CONF"
  run cq_pacman_conf_add "$CONF" "$OUT"
  [ "$status" -eq 1 ]
  [[ $output == *"already defines [omarchy]"* ]]
}
