# shellcheck shell=bash
# Fake system commands for CLI tests. `fake_system <fixture>` copies the fixture into
# CQ_ROOT and puts stubs on PATH that answer like a stock CachyOS install of it. Tests vary
# the system through the FAKE_* variables and the files under $FAKE_DIR.
# Stub bodies are single-quoted on purpose: they expand when the stub runs.
# shellcheck disable=SC2016

# fake_cmd <name> <body>: a stub command on PATH.
fake_cmd() {
  printf '#!/bin/bash\n%s\n' "$2" >"$FAKE_DIR/bin/$1"
  chmod +x "$FAKE_DIR/bin/$1"
}

fake_system() {
  mkroot "$1"
  export CQ_REPO="$BATS_TEST_DIRNAME/../.."
  export FAKE_DIR="$BATS_TEST_TMPDIR/fake"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_DIR/bin" "$HOME" "$CQ_ROOT/usr/lib/limine"
  export PATH="$FAKE_DIR/bin:$PATH"
  export FAKE_ROOT_FS=btrfs FAKE_FREE_GIB=120 FAKE_CURL_RC=0 FAKE_SUDO_RC=0 FAKE_BOOTCTL_RC=1 FAKE_HOME_FSROOT=/@home
  if grep -q 'rd.luks' "$CQ_ROOT/proc/cmdline"; then
    export FAKE_ROOT_SOURCE=/dev/mapper/luks-0 FAKE_BLOCK_TYPES=$'crypt\npart\ndisk'
  else
    export FAKE_ROOT_SOURCE=/dev/vda2 FAKE_BLOCK_TYPES=$'part\ndisk'
  fi
  printf '%s\n' base fish limine limine-mkinitcpio-hook limine-snapper-sync linux-cachyos linux-cachyos-lts snapper \
    >"$FAKE_DIR/packages"
  printf 'config,subvolume\nroot,/\n' >"$FAKE_DIR/snapper-configs"

  # `sudo true` is how the CLI asks for credentials up front (sudo -v ignores NOPASSWD).
  fake_cmd sudo '[[ $1 == true ]] && exit "$FAKE_SUDO_RC"
exec "$@"'
  fake_cmd pacman 'case $1 in
-Qq | -Qqe) cat "$FAKE_DIR/packages" ;;
-Qoq) printf "linux-cachyos\nlinux-cachyos-lts\n" ;;
-Qi) grep -qx "$2" "$FAKE_DIR/packages" && printf "Name            : %s\nPackager        : CachyOS <admin@cachyos.org>\n" "$2" ;;
*) echo "fake pacman: unexpected $*" >&2; exit 2 ;;
esac'
  fake_cmd findmnt 'target=${!#}
case "$*" in
*FSTYPE*) echo "$FAKE_ROOT_FS" ;;
*SOURCE*) echo "$FAKE_ROOT_SOURCE" ;;
*FSROOT*)
  if [[ $target == / ]]; then echo /@
  elif [[ -n $FAKE_HOME_FSROOT ]]; then echo "$FAKE_HOME_FSROOT"
  else exit 1; fi ;;
*) echo "fake findmnt: unexpected $*" >&2; exit 2 ;;
esac'
  fake_cmd lsblk 'printf "%s\n" "$FAKE_BLOCK_TYPES"'
  fake_cmd bootctl 'exit "$FAKE_BOOTCTL_RC"'
  fake_cmd snapper 'case "$*" in
*list-configs*) cat "$FAKE_DIR/snapper-configs" ;;
*create*) echo "snapper $*" >>"$FAKE_DIR/snapper.log"; echo 42 ;;
*) echo "fake snapper: unexpected $*" >&2; exit 2 ;;
esac'
  fake_cmd curl 'exit "$FAKE_CURL_RC"'
  fake_cmd df 'printf " Avail\n %s\n" "$FAKE_FREE_GIB"'
  fake_cmd systemctl 'printf "sshd.service enabled disabled\nufw.service enabled enabled\n"'

  # Limine's load_config, reading the fixture's /etc/default/limine.
  cat >"$CQ_ROOT/usr/lib/limine/limine-common-functions" <<'EOF'
load_config() {
  local line
  while IFS= read -r line; do
    if [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=\"?([^\"]*)\"?$ ]]; then
      export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
    fi
  done <"$CQ_ROOT/etc/default/limine"
}
EOF
}
