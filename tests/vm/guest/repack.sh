#!/bin/bash
# Rebuild a cached pacman package under a new pkgrel, with extra files or dependencies: a
# stand-in for a new upstream release in the hostile-release scenario. Run as root, so file
# ownership survives the extract and the repack.
#
#   repack.sh <package file> <outdir> <pkgrel> [add <file> <path in package>]... [depend <package>]...

set -euo pipefail

(($# >= 3)) || {
  echo "usage: repack.sh <package file> <outdir> <pkgrel> [add <file> <path>]... [depend <package>]..." >&2
  exit 2
}
pkg=$1 outdir=$2 pkgrel=$3
shift 3
tree=$(mktemp -d)
trap 'rm -rf "$tree"' EXIT
bsdtar -xpf "$pkg" -C "$tree"
while (($#)); do
  case $1 in
  add)
    install -D -m 644 -o root -g root "$2" "$tree/$3"
    shift 3
    ;;
  depend)
    echo "depend = $2" >>"$tree/.PKGINFO"
    shift 2
    ;;
  *)
    echo "repack.sh: unknown argument $1" >&2
    exit 2
    ;;
  esac
done
sed -i -E "s/^(pkgver = .*)-[^-]+$/\1-$pkgrel/" "$tree/.PKGINFO"
name=$(sed -n 's/^pkgname = //p' "$tree/.PKGINFO")
version=$(sed -n 's/^pkgver = //p' "$tree/.PKGINFO")
arch=$(sed -n 's/^arch = //p' "$tree/.PKGINFO")

cd "$tree"
rm -f .MTREE
meta=()
for f in .PKGINFO .BUILDINFO .INSTALL; do [[ -e $f ]] && meta+=("$f"); done
mapfile -t top < <(find . -mindepth 1 -maxdepth 1 ! -name '.*' -printf '%P\n' | sort)
bsdtar -czf .MTREE --format=mtree \
  --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' "${meta[@]}" "${top[@]}"
bsdtar --zstd -cf "$outdir/$name-$version-$arch.pkg.tar.zst" .MTREE "${meta[@]}" "${top[@]}"
echo "$outdir/$name-$version-$arch.pkg.tar.zst"
