# shellcheck shell=bash
# cachyos-quattro backup: a snapper snapshot, tarballs of /boot and the /etc and home files
# install touches, system facts, and the baselines and identity copies the protections
# compare against. Written to ~/.local/state/cachyos-quattro/backups/<UTC time>/, which on
# CachyOS lies in @home, outside the root snapshot, so it survives a rollback.

CQ_BACKUP_ETC=(/etc/pacman.conf /etc/pacman.d /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d /etc/default/limine
  /etc/limine-entry-tool.d /etc/os-release /etc/nsswitch.conf /etc/security/faillock.conf /etc/plymouth
  /etc/sysctl.d /etc/skel /etc/sddm.conf.d)

cmd_backup() {
  [[ $(cq_os_id) == cachyos ]] || cq_die "/etc/os-release is not CachyOS; not saving it as the CachyOS identity"
  sudo true || cq_die "backup needs sudo"

  local stamp dir lib root path rel etc=() home=() b
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  dir=$HOME/.local/state/cachyos-quattro/backups/$stamp
  lib=$(cq_lib_dir)
  root=$(cq_root /)
  mkdir -p "$dir"
  chmod 700 "$dir"
  : >"$dir/missing.txt"

  cq_log "snapshot"
  # The output goes to the user's own backup directory, so the redirect runs as the user.
  # shellcheck disable=SC2024
  sudo snapper -c root create --type single --description "cachyos-quattro pre-install" --print-number >"$dir/snapshot.txt"

  cq_log "boot.tar (the ESP is not in any snapshot)"
  sudo tar --xattrs --acls -cpf "$dir/boot.tar" -C "$root" boot

  cq_log "etc.tar"
  for path in "${CQ_BACKUP_ETC[@]}"; do
    rel=${path#/}
    if sudo test -e "$root$rel"; then etc+=("$rel"); else echo "$path" >>"$dir/missing.txt"; fi
  done
  # pacman's keyring holds the local signing key; it does not belong in a user-readable backup.
  sudo tar --xattrs --acls --exclude=etc/pacman.d/gnupg -cpf "$dir/etc.tar" -C "$root" "${etc[@]}"

  cq_log "home.tar"
  for path in .config .bashrc .local/share/applications .local/state/omarchy; do
    if [[ -e $HOME/$path ]]; then home+=("$path"); else echo "$HOME/$path" >>"$dir/missing.txt"; fi
  done
  if ((${#home[@]})); then
    tar -cpf "$dir/home.tar" -C "$HOME" "${home[@]}"
  else
    tar -cpf "$dir/home.tar" --files-from=/dev/null
  fi

  cq_log "system facts"
  cp "$(cq_root /proc/cmdline)" "$dir/cmdline.txt"
  pacman -Qqe >"$dir/pacman-Qqe.txt"
  systemctl list-unit-files --state=enabled --no-legend >"$dir/enabled-units.txt"

  cq_log "baselines and identity copies in $lib"
  sudo install -d -m 755 "$lib/baseline" "$lib/identity"
  for b in hooks limine packagers; do
    sudo "$CQ_REPO/package/libexec/verify" --current "$b" | sudo tee "$lib/baseline/$b" >/dev/null
  done
  sudo install -m 644 "$(cq_root /proc/cmdline)" "$lib/baseline/cmdline"
  sudo install -m 644 "$(cq_root /etc/os-release)" "$(cq_root /etc/nsswitch.conf)" "$lib/identity/"
  cp -r "$lib/baseline" "$dir/baseline"

  local files
  files=$(cd "$dir" && find . -type f -printf '%P\n' | sort)
  (cd "$dir" && xargs -d '\n' sha256sum <<<"$files" >manifest.sha256)
  ln -sfn "$stamp" "$HOME/.local/state/cachyos-quattro/backups/latest"
  cq_ok "backup in $dir (snapshot $(<"$dir/snapshot.txt"))"
}
