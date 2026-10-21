# shellcheck shell=bash
# cachyos-quattro recover --backup <dir> [--target <mountpoint>]: put /boot and the boot-relevant
# /etc files back from a backup into a system mounted at <mountpoint> (default /), and remove
# Omarchy's boot drop-ins. Meant for the CachyOS live ISO when the installed system does not
# boot; docs/recovery.md has the steps around it. The initramfs must be rebuilt afterwards.

# shellcheck source=lib/cmd-uninstall.sh
source "$CQ_REPO/lib/cmd-uninstall.sh"

CQ_RECOVER_ETC=(/etc/mkinitcpio.conf /etc/mkinitcpio.conf.d /etc/default/limine /etc/limine-entry-tool.d
  /etc/os-release /etc/nsswitch.conf)

cmd_recover() {
  local backup="" target=/ f
  while (($#)); do
    case $1 in
    --backup) backup=${2:-} && shift ;;
    --target) target=${2:-} && shift ;;
    *) cq_die "recover: unknown option $1" ;;
    esac
    shift
  done
  [[ -n $backup ]] || cq_die "recover: --backup <dir> is required (a directory under ~/.local/state/cachyos-quattro/backups/)"
  for f in boot.tar etc.tar missing.txt; do
    [[ -f $backup/$f ]] || cq_die "no $f in $backup; is it a cachyos-quattro backup?"
  done
  [[ -d $target/etc && -d $target/boot ]] || cq_die "$target does not look like a mounted root with /boot"
  sudo true || cq_die "recover needs sudo"

  cq_log "== /boot from $backup/boot.tar"
  sudo tar -xpf "$backup/boot.tar" -C "$target"
  cq_log "== /etc"
  CQ_ROOT=${target%/} cq_uninstall_restore_etc "$backup" "${CQ_RECOVER_ETC[@]}"
  sudo rm -f "$target/etc/mkinitcpio.conf.d/omarchy_hooks.conf" "$target"/etc/limine-entry-tool.d/omarchy-*.conf
  cq_log "removed Omarchy's initramfs and Limine drop-ins, if any"

  cq_log ""
  if [[ $target == / ]]; then
    cq_log "Next, rebuild the initramfs before rebooting: sudo limine-mkinitcpio"
  else
    cq_log "Next, rebuild the initramfs before rebooting: sudo arch-chroot $target limine-mkinitcpio"
  fi
}
