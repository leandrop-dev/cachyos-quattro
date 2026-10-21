#!/usr/bin/env bats

# Single-quoted pacman variables ($arch, $repo) and stub bodies are literal on purpose.
# shellcheck disable=SC2016

load helpers

VERIFY="$BATS_TEST_DIRNAME/../../package/libexec/verify"
LEDGER="$BATS_TEST_DIRNAME/../../ledger"
MID=00000000000000000000000000000000
LUKS_HOOKS="base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth sd-encrypt filesystems sd-btrfs-overlayfs"
PLAIN_HOOKS="base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems sd-btrfs-overlayfs"
PACKAGER="CachyOS <admin@cachyos.org>"

# prepare <fixture>: a fixture root in the state `cachyos-quattro install` leaves behind,
# with its baselines, plus stubs for pacman, pacman-conf, lsinitcpio and Limine's load_config.
prepare() {
  mkroot "$1"
  local lib=$CQ_ROOT/var/lib/cachyos-quattro bin=$BATS_TEST_TMPDIR/bin kernel
  mkdir -p "$CQ_ROOT/usr/share/cachyos-quattro/ledger" "$lib/baseline" "$lib/identity" "$bin" \
    "$CQ_ROOT/usr/lib/limine" "$CQ_ROOT/home/tester"
  cp "$LEDGER/files.tsv" "$CQ_ROOT/usr/share/cachyos-quattro/ledger/"

  sed -i '/^\[options\]/a Include = /etc/pacman.d/cachyos-quattro.conf' "$CQ_ROOT/etc/pacman.conf"
  printf '\n[omarchy]\nSigLevel = Optional TrustAll\nServer = https://pkgs.omarchy.org/$arch\n' >>"$CQ_ROOT/etc/pacman.conf"
  ln -sfn /dev/null "$CQ_ROOT/etc/pacman.d/hooks/00-omarchy-update-guard.hook"
  cp "$CQ_ROOT/etc/os-release" "$CQ_ROOT/etc/nsswitch.conf" "$lib/identity/"

  # lsinitcpio is stubbed as cat, so each image holds its own file listing.
  for kernel in linux-cachyos linux-cachyos-lts; do
    mkdir -p "$CQ_ROOT/boot/$MID/$kernel"
    printf 'usr/lib/systemd/systemd\n' >"$CQ_ROOT/boot/$MID/$kernel/initramfs"
  done
  mkdir -p "$CQ_ROOT/boot/$MID/limine_history"
  printf 'usr/lib/systemd/systemd\n' >"$CQ_ROOT/boot/$MID/limine_history/initramfs_sha256_0"

  if grep -q 'rd.luks' "$CQ_ROOT/proc/cmdline"; then
    echo "$LUKS_HOOKS" >"$lib/baseline/hooks"
    for kernel in linux-cachyos linux-cachyos-lts; do
      echo 'usr/lib/systemd/systemd-cryptsetup' >>"$CQ_ROOT/boot/$MID/$kernel/initramfs"
    done
  else
    echo "$PLAIN_HOOKS" >"$lib/baseline/hooks"
  fi
  cp "$CQ_ROOT/proc/cmdline" "$lib/baseline/cmdline"
  printf 'TARGET_OS_NAME=\nENABLE_UKI=\nBOOT_ORDER=*, *lts, *fallback, Snapshots\nMAX_SNAPSHOT_ENTRIES=\n' >"$lib/baseline/limine"

  export FAKE_INSTALLED="$BATS_TEST_TMPDIR/installed.tsv"
  for pkg in limine limine-mkinitcpio-hook limine-snapper-sync linux-cachyos linux-cachyos-lts; do
    printf '%s\t%s\n' "$pkg" "$PACKAGER" >>"$FAKE_INSTALLED"
  done
  cp "$FAKE_INSTALLED" "$lib/baseline/packagers"
  touch "$lib/installed"

  cat >"$CQ_ROOT/usr/lib/limine/limine-common-functions" <<'EOF'
# Stub of limine-mkinitcpio-hook's load_config: key=value files, later ones win.
load_config() {
  local file line
  for file in "$CQ_ROOT"/etc/limine-entry-tool.d/*.conf "$CQ_ROOT/etc/default/limine"; do
    [[ -f $file ]] || continue
    while IFS= read -r line; do
      if [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=\"?([^\"]*)\"?$ ]]; then
        export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
      fi
    done <"$file"
  done
}
EOF

  cat >"$bin/pacman-conf" <<'EOF'
#!/bin/bash
config=/etc/pacman.conf
[[ $1 == --config ]] && { config=$2; shift 2; }
case $1 in
NoExtract)
  if grep -qx 'Include = /etc/pacman.d/cachyos-quattro.conf' "$config"; then
    awk -F'\t' '!/^#/ && $2 == "noextract" {print $1}' "$CQ_ROOT/usr/share/cachyos-quattro/ledger/files.tsv"
  fi
  ;;
--repo-list) sed -n 's/^\[\(.*\)\]$/\1/p' "$config" | grep -vx options ;;
*) echo "fake pacman-conf: unexpected $*" >&2; exit 2 ;;
esac
EOF
  cat >"$bin/pacman" <<'EOF'
#!/bin/bash
case $1 in
-Qq) cut -f1 "$FAKE_INSTALLED" ;;
-Qoq) printf 'linux-cachyos\nlinux-cachyos-lts\n' ;;
-Qi)
  line=$(awk -F'\t' -v p="$2" '$1 == p' "$FAKE_INSTALLED")
  [[ -n $line ]] || { echo "error: package '$2' was not found" >&2; exit 1; }
  printf 'Name            : %s\nPackager        : %s\n' "$2" "${line#*$'\t'}"
  ;;
*) echo "fake pacman: unexpected $*" >&2; exit 2 ;;
esac
EOF
  printf '#!/bin/bash\ncat "$1"\n' >"$bin/lsinitcpio"
  chmod +x "$bin"/*
  export PATH="$bin:$PATH"
}

@test "a Limine+LUKS root in its installed state passes every check" {
  prepare cachyos-limine-luks
  run "$VERIFY"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ $output != *FAIL* ]]
  for check in pacman-include noextract-absent guard-mask hooks initramfs limine identity mirrors repo-order boot-packages no-omarchy-kernel held-migrations; do
    grep -qE "^(ok|warn) $check: " <<<"$output"
  done
}

@test "a Limine root without LUKS passes every check" {
  prepare cachyos-limine-plain
  run "$VERIFY"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "omarchy_hooks.conf on disk fails noextract-absent and hooks" {
  prepare cachyos-limine-luks
  echo 'HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)' \
    >"$CQ_ROOT/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q '^FAIL noextract-absent: .*etc/mkinitcpio.conf.d/omarchy_hooks.conf' <<<"$output"
  grep -q '^FAIL hooks: ' <<<"$output"
}

@test "a missing Include fails pacman-include" {
  prepare cachyos-limine-luks
  sed -i '\|^Include = /etc/pacman.d/cachyos-quattro.conf$|d' "$CQ_ROOT/etc/pacman.conf"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q '^FAIL pacman-include: ' <<<"$output"
}

@test "an unmasked guard hook fails guard-mask" {
  prepare cachyos-limine-luks
  rm "$CQ_ROOT/etc/pacman.d/hooks/00-omarchy-update-guard.hook"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q '^FAIL guard-mask: ' <<<"$output"
}

@test "os-release with ID=omarchy fails identity" {
  prepare cachyos-limine-luks
  printf 'NAME="Omarchy"\nID=omarchy\n' >"$CQ_ROOT/etc/os-release"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q '^FAIL identity: .*os-release' <<<"$output"
}

@test "[omarchy] before [cachyos] fails repo-order" {
  prepare cachyos-limine-luks
  sed -i '/^\[omarchy\]$/,$d' "$CQ_ROOT/etc/pacman.conf"
  sed -i '0,/^\[cachyos-v3\]/s//[omarchy]\nServer = https:\/\/pkgs.omarchy.org\/$arch\n\n[cachyos-v3]/' "$CQ_ROOT/etc/pacman.conf"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q '^FAIL repo-order: ' <<<"$output"
}

@test "a mirrorlist with a single omarchy server fails mirrors" {
  prepare cachyos-limine-luks
  echo 'Server = https://stable-mirror.omarchy.org/$repo/os/$arch' >"$CQ_ROOT/etc/pacman.d/mirrorlist"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q '^FAIL mirrors: .*mirrorlist' <<<"$output"
}

@test "an initramfs without systemd-cryptsetup fails on a LUKS root" {
  prepare cachyos-limine-luks
  echo 'usr/lib/systemd/systemd' >"$CQ_ROOT/boot/$MID/linux-cachyos-lts/initramfs"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q "^FAIL initramfs: .*linux-cachyos-lts/initramfs" <<<"$output"
}

@test "Omarchy's Limine defaults fail limine" {
  prepare cachyos-limine-luks
  mkdir -p "$CQ_ROOT/etc/limine-entry-tool.d"
  echo 'TARGET_OS_NAME="Omarchy"' >"$CQ_ROOT/etc/limine-entry-tool.d/omarchy-defaults.conf"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q '^FAIL limine: .*TARGET_OS_NAME' <<<"$output"
}

@test "a boot package from another packager fails boot-packages" {
  prepare cachyos-limine-luks
  sed -i 's/^limine-mkinitcpio-hook\t.*/limine-mkinitcpio-hook\tOmarchy <pkgs@omarchy.org>/' "$FAKE_INSTALLED"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q '^FAIL boot-packages: .*limine-mkinitcpio-hook' <<<"$output"
}

@test "an installed linux-omarchy fails no-omarchy-kernel" {
  prepare cachyos-limine-luks
  printf 'linux-omarchy\tOmarchy <pkgs@omarchy.org>\n' >>"$FAKE_INSTALLED"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q '^FAIL no-omarchy-kernel: ' <<<"$output"
}

@test "held migrations warn without failing" {
  prepare cachyos-limine-luks
  mkdir -p "$CQ_ROOT/home/tester/.local/state/cachyos-quattro"
  printf '2026-10-21T00:00:00+00:00 held 1789325478.sh abc unreviewed\n' \
    >"$CQ_ROOT/home/tester/.local/state/cachyos-quattro/held.log"
  run "$VERIFY"
  [ "$status" -eq 0 ]
  grep -q '^warn held-migrations: 1 held for tester' <<<"$output"
}

@test "a held migration that has since been marked is not counted" {
  prepare cachyos-limine-luks
  mkdir -p "$CQ_ROOT/home/tester/.local/state/cachyos-quattro" "$CQ_ROOT/home/tester/.local/state/omarchy/migrations"
  printf '2026-10-21T00:00:00+00:00 held 1789325478.sh abc unreviewed\n' \
    >"$CQ_ROOT/home/tester/.local/state/cachyos-quattro/held.log"
  touch "$CQ_ROOT/home/tester/.local/state/omarchy/migrations/1789325478.sh"
  run "$VERIFY"
  grep -q '^ok held-migrations: ' <<<"$output"
}

@test "missing baselines fail closed" {
  prepare cachyos-limine-luks
  rm -r "$CQ_ROOT/var/lib/cachyos-quattro/baseline"
  run "$VERIFY"
  [ "$status" -eq 1 ]
  grep -q '^FAIL hooks: no baseline' <<<"$output"
}

@test "--hook prints one line when everything passes" {
  prepare cachyos-limine-luks
  run "$VERIFY" --hook
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ ${lines[0]} == "cachyos-quattro: all 12 checks passed" ]]
}

@test "--hook prints failures and a banner" {
  prepare cachyos-limine-luks
  printf 'ID=omarchy\n' >"$CQ_ROOT/etc/os-release"
  run "$VERIFY" --hook
  [ "$status" -eq 1 ]
  grep -q '^FAIL identity: ' <<<"$output"
  [[ $output != *"ok guard-mask"* ]]
  [[ $output == *"cachyos-quattro status"* ]]
}

@test "--current prints each baseline the checks compare against" {
  prepare cachyos-limine-luks
  run "$VERIFY" --current hooks
  [ "$status" -eq 0 ]
  [ "$output" = "$LUKS_HOOKS" ]
  run "$VERIFY" --current limine
  [ "$output" = "$(cat "$CQ_ROOT/var/lib/cachyos-quattro/baseline/limine")" ]
  run "$VERIFY" --current packagers
  [ "$output" = "$(cat "$CQ_ROOT/var/lib/cachyos-quattro/baseline/packagers")" ]
}

@test "--current hooks follows mkinitcpio's version-sorted drop-in order" {
  prepare cachyos-limine-luks
  echo 'HOOKS+=(late)' >"$CQ_ROOT/etc/mkinitcpio.conf.d/10-z.conf"
  echo 'HOOKS=(reset)' >"$CQ_ROOT/etc/mkinitcpio.conf.d/9-a.conf"
  run "$VERIFY" --current hooks
  [ "$output" = "reset sd-btrfs-overlayfs late" ]
}

@test "--hook skips the checks until install has finished" {
  prepare cachyos-limine-luks
  rm "$CQ_ROOT/var/lib/cachyos-quattro/installed"
  sed -i '\|^Include = /etc/pacman.d/cachyos-quattro.conf$|d' "$CQ_ROOT/etc/pacman.conf"
  run "$VERIFY" --hook
  [ "$status" -eq 0 ]
  [[ $output == *"not set up yet"* ]]
  run "$VERIFY"
  [ "$status" -eq 1 ]
}
