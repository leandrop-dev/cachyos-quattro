# shellcheck shell=bash
# The two marked blocks cachyos-quattro adds to /etc/pacman.conf, and their exact removal:
#   - after the [options] line, the Include of the NoExtract drop-in;
#   - at the end of the file, Omarchy's stable repository, so [omarchy] is the last
#     repository and CachyOS's builds of shared packages win.
# Both functions read <in> and write <out>; the caller installs <out> over pacman.conf.

CQ_PACMAN_INCLUDE_BLOCK='# BEGIN cachyos-quattro
Include = /etc/pacman.d/cachyos-quattro.conf
# END cachyos-quattro'
# Omarchy's own stable configuration (default/pacman/pacman-stable.conf) uses this server
# and inherits SigLevel = Required DatabaseOptional; it is spelled out here in case the
# global SigLevel is weaker.
# shellcheck disable=SC2016
CQ_PACMAN_REPO_BLOCK='# BEGIN cachyos-quattro repo
[omarchy]
SigLevel = Required DatabaseOptional
Server = https://pkgs.omarchy.org/stable/$arch
# END cachyos-quattro repo'

# The lines of both blocks, one per line.
cq_pacman_conf_blocks() { printf '%s\n%s\n' "$CQ_PACMAN_INCLUDE_BLOCK" "$CQ_PACMAN_REPO_BLOCK"; }

cq_pacman_conf_add() {
  local in=$1 out=$2
  if grep -qx '# BEGIN cachyos-quattro' "$in"; then
    cp "$in" "$out"
    return
  fi
  if ! grep -qx '\[options\]' "$in"; then
    echo "cachyos-quattro: $in has no [options] section" >&2
    return 1
  fi
  if grep -qx '\[omarchy\]' "$in"; then
    echo "cachyos-quattro: $in already defines [omarchy]; remove it first" >&2
    return 1
  fi
  awk -v block="$CQ_PACMAN_INCLUDE_BLOCK" '{ print } $0 == "[options]" && !done { print block; done = 1 }' "$in" >"$out"
  printf '%s\n' "$CQ_PACMAN_REPO_BLOCK" >>"$out"
}

cq_pacman_conf_remove() {
  awk '/^# BEGIN cachyos-quattro( repo)?$/ { skip = 1; next } /^# END cachyos-quattro( repo)?$/ { skip = 0; next } !skip' "$1" >"$2"
}
