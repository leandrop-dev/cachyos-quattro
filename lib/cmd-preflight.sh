# shellcheck shell=bash
# cachyos-quattro preflight: print what was detected, then refuse unless this is a
# supported system. Every failed requirement is reported, not just the first.

CQ_OMARCHY_DB=https://pkgs.omarchy.org/x86_64/omarchy.db
CQ_MIN_FREE_GIB=10

cmd_preflight() {
  sudo true || cq_die "preflight needs sudo (it reads /boot and snapper's configuration)"

  local id bootloader luks style fs configs home desktop omarchy hooks free problems=()
  id=$(cq_os_id)
  bootloader=$(cq_bootloader)
  luks=$(cq_root_luks)
  style=$(cq_luks_style)
  fs=$(cq_root_fs)
  configs=$(cq_snapper_configs)
  home=$(cq_home_separate)
  desktop=$(cq_desktop_present)
  omarchy=$(cq_omarchy_present)
  hooks=$(cq_verify --current hooks)
  free=$(df --output=avail -B1G "$(cq_root /)" | tail -n1 | tr -d ' ')

  cq_log "os-release ID: ${id:-none}"
  cq_log "bootloader: $bootloader"
  cq_log "root LUKS: $luks ($style)"
  cq_log "root file system: $fs"
  cq_log "snapper configs: $(paste -sd ' ' <<<"$configs")"
  cq_log "separate /home: $home"
  cq_log "desktop present: $desktop"
  cq_log "Omarchy present: $omarchy"
  cq_log "effective HOOKS: $hooks"
  cq_log "free on /: $free GiB"
  cq_log ""

  [[ $id == cachyos ]] || problems+=("/etc/os-release is not CachyOS (ID=${id:-none})")
  [[ $bootloader == limine ]] || problems+=("boot loader is $bootloader; v1 supports Limine only")
  [[ $desktop == no ]] || problems+=("a desktop is already installed; v1 supports CachyOS No Desktop only")
  [[ $omarchy == no ]] || problems+=("Omarchy is already installed")
  if [[ $luks == yes ]]; then
    case $style in
    systemd) [[ " $hooks " == *" sd-encrypt "* ]] ||
      problems+=("LUKS root unlocks with rd.luks (systemd) but HOOKS lack sd-encrypt") ;;
    legacy) [[ " $hooks " == *" encrypt "* ]] ||
      problems+=("LUKS root unlocks with cryptdevice= (legacy) but HOOKS lack encrypt") ;;
    *) problems+=("LUKS root, but the kernel command line has neither rd.luks nor cryptdevice=") ;;
    esac
  fi
  [[ $fs == btrfs ]] || problems+=("root file system is $fs, not btrfs")
  grep -qx root <<<"$configs" || problems+=("no snapper config named root")
  ((free >= CQ_MIN_FREE_GIB)) || problems+=("only $free GiB free on /; $CQ_MIN_FREE_GIB GiB needed")
  curl -fsI "$CQ_OMARCHY_DB" >/dev/null || problems+=("$CQ_OMARCHY_DB is not reachable")
  [[ $home == yes ]] || cq_warn "/home is not a separate subvolume, so a root rollback also rolls back the backup"

  if ((${#problems[@]})); then
    printf 'FAIL %s\n' "${problems[@]}"
    return 1
  fi
  cq_ok "preflight passed"
}
