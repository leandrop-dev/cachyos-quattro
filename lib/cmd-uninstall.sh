# shellcheck shell=bash
# cachyos-quattro uninstall [--yes]: remove Omarchy and put back the CachyOS configuration from
# the pre-install backup. It cannot undo changes to user files beyond home.tar, nor every
# change Omarchy's system setup steps made; the summary says what was and was not restored.

# shellcheck source=lib/cmd-install.sh
source "$CQ_REPO/lib/cmd-install.sh"

# The /etc paths omarchy-settings' .INSTALL and install's login phase change.
CQ_UNINSTALL_ETC=(/etc/os-release /etc/nsswitch.conf /etc/security/faillock.conf /etc/plymouth/plymouthd.conf
  /etc/skel/.bashrc /etc/sddm.conf.d)

# cq_uninstall_units_to_disable <backup enabled-units.txt> <current list>: enabled now, not before.
cq_uninstall_units_to_disable() { comm -13 <(awk '{ print $1 }' "$1" | sort) <(awk '{ print $1 }' "$2" | sort); }

# cq_uninstall_units_to_enable <backup enabled-units.txt> <current list>: enabled before, not now.
cq_uninstall_units_to_enable() { comm -23 <(awk '{ print $1 }' "$1" | sort) <(awk '{ print $1 }' "$2" | sort); }

# cq_uninstall_packages <backup dir>: what install added explicitly, in install order, without
# cachyos-quattro itself, which is removed last, after the pacman.conf blocks.
cq_uninstall_packages() {
  grep -vxF -f "$1/pacman-Qqe.txt" "$1/installed-packages.txt" | grep -vx cachyos-quattro || true
}

# cq_uninstall_restore_etc <backup dir> [path...]: put each path back from etc.tar under CQ_ROOT;
# remove it when the backup recorded it as missing; otherwise leave it and say so.
cq_uninstall_restore_etc() {
  local backup=$1 path rel members
  shift
  (($#)) || set -- "${CQ_UNINSTALL_ETC[@]}"
  members=$(tar -tf "$backup/etc.tar")
  for path in "$@"; do
    rel=${path#/}
    if grep -qxF -e "$rel" -e "$rel/" <<<"$members"; then
      sudo tar -xpf "$backup/etc.tar" -C "$(cq_root /)" "$rel"
      cq_log "restored $path"
    elif grep -qxF "$path" "$backup/missing.txt"; then
      sudo rm -rf "$(cq_root "$path")"
      cq_log "removed $path (it did not exist before install)"
    else
      cq_log "$path: not in the backup; left as is"
    fi
  done
}

cmd_uninstall() {
  local yes=0 installed backup units pkgs=() unit restored_home=no
  while (($#)); do
    case $1 in
    --yes) yes=1 ;;
    *) cq_die "uninstall: unknown option $1" ;;
    esac
    shift
  done
  installed=$(cq_lib_dir)/installed
  [[ -e $installed ]] || cq_die "cachyos-quattro is not installed (no $installed)"
  # The backup taken by install, not backups/latest: a later manual backup holds Omarchy's state.
  backup=$(sed -n 's/^backup=//p' "$installed")
  for f in etc.tar home.tar enabled-units.txt pacman-Qqe.txt installed-packages.txt missing.txt baseline/hooks baseline/limine; do
    [[ -e $backup/$f ]] || cq_die "the install backup $backup has no $f"
  done

  cq_log "This removes Omarchy and restores the CachyOS configuration from $backup."
  if ((!yes)); then
    cq_confirm "Remove Omarchy?" || cq_die "nothing changed"
    cq_confirm "Really remove Omarchy and its packages?" || cq_die "nothing changed"
  fi
  sudo true || cq_die "uninstall needs sudo"
  # Without the marker the verify hook stays quiet during the removal transactions.
  sudo rm -f "$installed"

  cq_log "== services enabled since install"
  units=$(mktemp)
  systemctl list-unit-files --state=enabled --no-legend >"$units"
  while IFS= read -r unit; do
    sudo systemctl disable "$unit" || cq_warn "could not disable $unit"
  done < <(cq_uninstall_units_to_disable "$backup/enabled-units.txt" "$units")

  cq_log "== packages install added"
  mapfile -t pkgs < <(grep -xF -f <(pacman -Qq) <(cq_uninstall_packages "$backup"))
  if ((${#pkgs[@]})); then
    sudo pacman -Rns --noconfirm "${pkgs[@]}" || cq_die "pacman could not remove Omarchy's packages; see above"
  fi

  cq_log "== services enabled before install"
  systemctl list-unit-files --state=enabled --no-legend >"$units"
  while IFS= read -r unit; do
    # Omarchy masks some units (enable-services.sh: NetworkManager-wait-online.service).
    if [[ $(systemctl is-enabled "$unit" || true) == masked ]]; then
      sudo systemctl unmask "$unit" || cq_warn "could not unmask $unit"
    fi
    sudo systemctl enable "$unit" || cq_warn "could not re-enable $unit"
  done < <(cq_uninstall_units_to_enable "$backup/enabled-units.txt" "$units")
  rm -f "$units"

  cq_log "== /etc"
  cq_uninstall_restore_etc "$backup"
  sudo rm -f "$(cq_root /var/lib/sddm/state.conf)"
  rm -f "$HOME/$CQ_POST_UPDATE_HOOK"

  cq_log "== pacman.conf and Omarchy's key"
  local work
  work=$(mktemp)
  cq_pacman_conf_remove "$(cq_root /etc/pacman.conf)" "$work"
  sudo install -m 644 "$work" "$(cq_root /etc/pacman.conf)"
  rm -f "$work"
  sudo pacman-key --delete "$CQ_OMARCHY_KEY" || cq_warn "could not delete Omarchy's key from pacman's keyring"

  cq_log "== the cachyos-quattro package"
  sudo pacman -Rns --noconfirm cachyos-quattro || cq_die "pacman could not remove cachyos-quattro"

  if ((!yes)) && cq_confirm "Restore your home configs from $backup/home.tar (overwrites files changed since install)?"; then
    tar -xpf "$backup/home.tar" -C "$HOME"
    restored_home=yes
  fi

  cq_log "== initramfs"
  sudo limine-mkinitcpio || cq_die "limine-mkinitcpio failed; do not reboot before fixing it"
  local rc=0 now
  now=$("$CQ_REPO/package/libexec/verify" --current hooks)
  if [[ $now == "$(<"$backup/baseline/hooks")" ]]; then cq_ok "HOOKS match the pre-install baseline"; else
    cq_warn "HOOKS are ($now), the pre-install baseline was ($(<"$backup/baseline/hooks"))"
    rc=1
  fi
  now=$(sudo "$CQ_REPO/package/libexec/verify" --current limine)
  if [[ $now == "$(<"$backup/baseline/limine")" ]]; then cq_ok "Limine settings match the pre-install baseline"; else
    cq_warn "Limine settings differ from the pre-install baseline: $(paste -sd ' ' <<<"$now")"
    rc=1
  fi
  sudo rm -rf "$(cq_lib_dir)" "$(cq_root /var/lib/omarchy/migrations/1789325478)"

  cq_log ""
  cq_log "Removed: ${#pkgs[@]} packages, the cachyos-quattro package, its pacman.conf blocks and Omarchy's key."
  cq_log "Restored: the /etc files listed above, the services enabled before install, the initramfs."
  cq_log "Left in place: Omarchy's configs in your home (home.tar restored: $restored_home), the backup in"
  cq_log "$backup, and other changes Omarchy's system setup steps made (see /var/log/omarchy-install.log)."
  return "$rc"
}
