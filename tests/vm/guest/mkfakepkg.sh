#!/bin/bash
# Build a minimal pacman package for VM scenarios, without makepkg or fakeroot.
#
#   mkfakepkg.sh <outdir> <name> <version> <install-script|-> <path>...
#
# Each <path> becomes a one-line text file. Entries are owned by root, as makepkg's are.

set -euo pipefail

(($# >= 5)) || {
  echo "usage: mkfakepkg.sh <outdir> <name> <version> <install-script|-> <path>..." >&2
  exit 2
}
outdir=$(cd "$1" && pwd) name=$2 version=$3 install=$4
shift 4

tree=$(mktemp -d)
trap 'rm -rf "$tree"' EXIT
for path in "$@"; do
  mkdir -p "$tree/$(dirname "$path")"
  echo "# cachyos-quattro test file $path" >"$tree/$path"
done
cat >"$tree/.PKGINFO" <<EOF
pkgname = $name
pkgbase = $name
pkgver = $version-1
pkgdesc = cachyos-quattro test package
url = https://github.com/leandrop-dev/cachyos-quattro
builddate = $(date +%s)
packager = cachyos-quattro tests
size = 1
arch = any
license = MIT
EOF
meta=(.PKGINFO)
if [[ $install != - ]]; then
  cp "$install" "$tree/.INSTALL"
  meta+=(.INSTALL)
fi
mapfile -t top < <(printf '%s\n' "$@" | cut -d/ -f1 | sort -u)

cd "$tree"
owner=(--uid 0 --gid 0 --uname root --gname root)
bsdtar "${owner[@]}" -czf .MTREE --format=mtree \
  --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' "${meta[@]}" "${top[@]}"
bsdtar "${owner[@]}" --zstd -cf "$outdir/$name-$version-1-any.pkg.tar.zst" .MTREE "${meta[@]}" "${top[@]}"
echo "$outdir/$name-$version-1-any.pkg.tar.zst"
