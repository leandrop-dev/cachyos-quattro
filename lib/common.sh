# shellcheck shell=bash
# Shared helpers for bin/cachyos-quattro and lib/cmd-*.sh. Paths on the system go through
# cq_root, so tests can point CQ_ROOT at a fixture root.

cq_log() { printf '%s\n' "$*"; }
cq_ok() { printf 'ok   %s\n' "$*"; }
cq_warn() { printf 'warn %s\n' "$*" >&2; }
cq_die() {
  printf 'cachyos-quattro: %s\n' "$*" >&2
  exit 1
}

# cq_confirm <question>: true only for an explicit yes; anything else, or no terminal, is no.
cq_confirm() {
  local reply
  read -r -p "$1 [y/N] " reply || return 1
  [[ $reply == [yY] || $reply == [yY][eE][sS] ]]
}

# cq_root <absolute path>: the path under CQ_ROOT.
cq_root() { printf '%s%s\n' "${CQ_ROOT:-}" "$1"; }

cq_lib_dir() { cq_root /var/lib/cachyos-quattro; }

cq_phase_done() { [[ -e $(cq_lib_dir)/phases/$1 ]]; }
cq_phase_mark() { sudo install -D -m 644 /dev/null "$(cq_lib_dir)/phases/$1"; }

cq_installed() { pacman -Qq | grep -qxF -- "$1"; }

# The repository's own copy of verify: preflight and backup run before the package exists.
cq_verify() { "$CQ_REPO/package/libexec/verify" "$@"; }

cq_os_id() { sed -n 's/^ID=//p' "$(cq_root /etc/os-release)" | tr -d '"'; }
