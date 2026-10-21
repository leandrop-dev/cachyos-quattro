# shellcheck shell=bash
# System detection. Each function prints one value and never guesses: when the evidence
# does not settle the answer it says unknown or multiple. Reads under /boot go through sudo,
# because CachyOS mounts the ESP with umask=0077.

cq_bootloader() {
  local found=()
  if sudo test -f "$(cq_root /boot/limine.conf)" && cq_installed limine; then found+=(limine); fi
  if sudo bootctl --quiet is-installed; then found+=(systemd-boot); fi
  if sudo test -f "$(cq_root /boot/grub/grub.cfg)" && cq_installed grub; then found+=(grub); fi
  case ${#found[@]} in
  0) echo unknown ;;
  1) echo "${found[0]}" ;;
  *) echo multiple ;;
  esac
}

cq_root_luks() {
  local source
  source=$(findmnt -no SOURCE --nofsroot /)
  if lsblk -s -no TYPE "$source" | grep -qx crypt; then echo yes; else echo no; fi
}

cq_luks_style() {
  local cmdline
  cmdline=$(<"$(cq_root /proc/cmdline)")
  if [[ $cmdline == *rd.luks.* ]]; then
    echo systemd
  elif [[ $cmdline == *cryptdevice=* ]]; then
    echo legacy
  else
    echo none
  fi
}

cq_root_fs() { findmnt -no FSTYPE /; }

cq_snapper_configs() { sudo snapper --csvout list-configs | awk -F, 'NR > 1 && $1 != "" { print $1 }'; }

cq_home_separate() {
  local home root
  if home=$(findmnt -no FSROOT /home) && root=$(findmnt -no FSROOT /) && [[ $home != "$root" ]]; then
    echo yes
  else
    echo no
  fi
}

cq_desktop_present() {
  local pkg
  if [[ -L $(cq_root /etc/systemd/system/display-manager.service) ]]; then
    echo yes
    return
  fi
  for pkg in plasma-desktop gnome-shell hyprland cachyos-hypr-noctalia greetd sddm; do
    if cq_installed "$pkg"; then
      echo yes
      return
    fi
  done
  echo no
}

cq_omarchy_present() {
  if cq_installed omarchy || [[ -e $HOME/.local/share/omarchy ]]; then echo yes; else echo no; fi
}
