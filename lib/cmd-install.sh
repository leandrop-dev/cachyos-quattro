# shellcheck shell=bash
# cachyos-quattro install [--yes]: install Omarchy v4 with the CachyOS protections, as
# resumable phases. Each phase says what it changes and asks first unless --yes; a phase
# that completed is skipped on the next run, so a failed install resumes where it stopped.
# The last phase rebuilds the initramfs and runs every check before "safe to reboot".

# shellcheck source=lib/cmd-preflight.sh
source "$CQ_REPO/lib/cmd-preflight.sh"
# shellcheck source=lib/cmd-backup.sh
source "$CQ_REPO/lib/cmd-backup.sh"
# shellcheck source=lib/pacman-conf.sh
source "$CQ_REPO/lib/pacman-conf.sh"

CQ_OMARCHY_KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
CQ_OMARCHY_PATH=/usr/share/omarchy
CQ_INSTALL_PHASES=(preflight backup guard pacman-conf keyring packages base-packages system user login rebuild "done")

# cq_install_plan_steps <omarchy install dir> <install-steps.tsv>: "<verdict>\t<script>" for
# every script Omarchy's {config,hardware,login,post-install}/all.sh run, in Omarchy's
# order (omarchy-apply-system). Fails on a script the ledger has not reviewed, or on any
# line in an all.sh other than run_logged, so a changed installer stops the install.
cq_install_plan_steps() {
  local dir=$1 ledger=$2 group line script verdict bad=0
  for group in config hardware login post-install; do
    while IFS= read -r line; do
      [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
      if [[ $line =~ ^run_logged\ \"\$OMARCHY_INSTALL/([^\"]+)\"$ ]]; then
        script=${BASH_REMATCH[1]}
        verdict=$(awk -F'\t' -v s="$script" '$1 == s { print $2; exit }' "$ledger")
        case $verdict in
        run | skip) printf '%s\t%s\n' "$verdict" "$script" ;;
        *)
          echo "cachyos-quattro: install step $script is not reviewed in $ledger" >&2
          bad=1
          ;;
        esac
      else
        echo "cachyos-quattro: unexpected line in $group/all.sh: $line" >&2
        bad=1
      fi
    done <"$dir/$group/all.sh"
  done
  return "$bad"
}

cq_install_backup_dir() { readlink -f "$HOME/.local/state/cachyos-quattro/backups/latest"; }

CQ_POST_UPDATE_HOOK=.config/omarchy/hooks/post-update.d/cachyos-quattro-verify

# omarchy-update runs ~/.config/omarchy/hooks/post-update.d/* (omarchy-hook post-update) after
# migrations and before it offers a reboot, so the checks run there too, including when the
# update starts from the Omarchy menu. A failing hook is reported, not fatal.
cq_install_post_update_hook() {
  local hook=$HOME/$CQ_POST_UPDATE_HOOK
  mkdir -p "$(dirname "$hook")"
  cat >"$hook" <<'EOF'
# Installed by cachyos-quattro: check the CachyOS protections after an Omarchy update,
# before omarchy-update offers a reboot.
if ! sudo /usr/lib/cachyos-quattro/verify; then
  echo "cachyos-quattro: a protection check failed. Do not reboot; run 'cachyos-quattro status'."
  exit 1
fi
EOF
}

# cq_pacman <args>: sudo pacman, up to five attempts. Downloads fail intermittently (a reset
# from pkgs.omarchy.org; HTTP 503 for .sig files from a CachyOS mirror, which pacman does not
# fetch from the next mirror), and each attempt keeps what it already downloaded.
# Safe to repeat: every call uses --needed, and a failed transaction changes nothing.
cq_pacman() {
  local attempt
  for attempt in 1 2 3 4 5; do
    sudo pacman "$@" && return 0
    ((attempt < 5)) || break
    cq_warn "pacman failed (attempt $attempt of 5); retrying in 15 s"
    sleep 15
  done
  return 1
}

# cq_run_phase <command>: run it in a subshell with errexit and leave its exit status in
# CQ_PHASE_RC, so a failing command anywhere in the phase fails the phase. Bash switches
# errexit off for everything run on the left of || or inside an if, so this must be called as
# a plain statement and always returns 0.
cq_run_phase() {
  local restore=+e
  [[ $- == *e* ]] && restore=-e
  set +e
  (
    set -e
    "$@"
  )
  CQ_PHASE_RC=$?
  set "$restore"
  return 0
}

cq_install_phase_guard() {
  cq_installed fakeroot || cq_pacman -S --needed --noconfirm fakeroot
  (cd "$CQ_REPO/package" && makepkg -f --noconfirm)
  local pkg
  pkg=$(find "$CQ_REPO/package" -maxdepth 1 -name 'cachyos-quattro-*-any.pkg.tar.zst' -newer "$CQ_REPO/package/PKGBUILD" | sort | tail -n1)
  [[ -n $pkg ]] || cq_die "makepkg did not produce a package in $CQ_REPO/package"
  sudo pacman -U --noconfirm "$pkg"
}

cq_install_phase_pacman_conf() {
  local conf work
  conf=$(cq_root /etc/pacman.conf)
  work=$(mktemp)
  cp "$conf" "$(cq_install_backup_dir)/pacman.conf.before-install"
  cq_pacman_conf_add "$conf" "$work"
  sudo install -m 644 "$work" "$conf"
  rm -f "$work"
  [[ $(pacman-conf --repo-list | tail -n1) == omarchy ]] || cq_die "[omarchy] is not the last repository in $conf"
  local missing
  missing=$(grep -vxF -f <(pacman-conf NoExtract) <(awk -F'\t' '!/^#/ && $2 == "noextract" { print $1 }' "$CQ_REPO/ledger/files.tsv")) || true
  [[ -z $missing ]] || cq_die "pacman does not apply NoExtract to: $missing"
}

cq_install_phase_keyring() {
  sudo pacman-key --recv-keys "$CQ_OMARCHY_KEY"
  sudo pacman-key --lsign-key "$CQ_OMARCHY_KEY"
}

cq_install_phase_packages() {
  cq_pacman -Syu --needed --noconfirm omarchy-keyring omarchy omarchy-settings
  local out
  if ! out=$(sudo /usr/lib/cachyos-quattro/verify); then
    printf '%s\n' "$out"
    cq_die "a protection check failed after installing Omarchy's packages; not continuing"
  fi
}

cq_install_phase_base_packages() {
  local list exclude pkgs=()
  list=$(cq_root "$CQ_OMARCHY_PATH/install/omarchy-base.packages")
  exclude=$(sed 's/[[:space:]]*#.*//' "$CQ_REPO/ledger/base-packages-exclude.txt" | grep .)
  mapfile -t pkgs < <(sed 's/[[:space:]]*#.*//' "$list" | grep . | grep -vxF -f <(printf '%s\n' "$exclude"))
  if [[ $(getent passwd "$USER" | cut -d: -f7) == */fish ]]; then
    mapfile -t -O "${#pkgs[@]}" pkgs < <(sed 's/[[:space:]]*#.*//' "$CQ_REPO/ledger/base-packages-shell-fish.txt" | grep .)
    cq_warn "omarchy-fish turns on fish_vi_key_bindings for every user"
  fi
  cq_pacman -S --needed --noconfirm "${pkgs[@]}"
}

cq_install_phase_system() {
  local install=$CQ_OMARCHY_PATH/install plan verdict script
  plan=$(cq_install_plan_steps "$(cq_root "$install")" "$CQ_REPO/ledger/install-steps.tsv") ||
    cq_die "Omarchy's installer has steps the ledger has not reviewed; not running any of them"
  while IFS=$'\t' read -r verdict script; do
    if [[ $verdict == skip ]]; then
      cq_log "skip $script (ledger/install-steps.tsv)"
      continue
    fi
    sudo env OMARCHY_PATH="$CQ_OMARCHY_PATH" OMARCHY_INSTALL="$install" OMARCHY_INSTALL_USER="$USER" \
      OMARCHY_LOG_TO_STDOUT=1 PATH="$CQ_OMARCHY_PATH/bin:/usr/local/sbin:/usr/local/bin:/usr/bin" \
      bash -c 'source "$OMARCHY_INSTALL/helpers/logging.sh" && run_logged "$OMARCHY_INSTALL/$1"' _ "$script" ||
      cq_die "install step $script failed; fix the cause and run 'cachyos-quattro install' again to resume"
  done <<<"$plan"
}

cq_install_phase_user() {
  local name=${CQ_USER_NAME:-} email=${CQ_USER_EMAIL:-}
  [[ -n $name ]] || read -r -p "Full name for git and Omarchy: " name
  [[ -n $email ]] || read -r -p "Email for git and Omarchy: " email
  # Seeds the Omarchy configs and a marker for every shipped migration; home.tar in the
  # backup is the undo for anything it replaces.
  cp -af "$(cq_root /etc/skel)/." "$HOME/"
  # The setup upstream runs for an existing machine's first boot (omarchy-provision-owner's
  # finalize_user): --first-install marks shipped migrations done, and the provision-owner
  # context sets the theme without a running session.
  env OMARCHY_PATH="$CQ_OMARCHY_PATH" OMARCHY_INSTALL="$CQ_OMARCHY_PATH/install" OMARCHY_SETUP_CONTEXT=provision-owner \
    OMARCHY_USER_NAME="$name" OMARCHY_USER_EMAIL="$email" OMARCHY_LOG_TO_STDOUT=1 \
    "$CQ_OMARCHY_PATH/bin/omarchy-provision-user" --force --first-install
  # Migration 1789325478 installs linux-omarchy and rewrites BOOT_ORDER; with this marker it
  # exits early for any user, including one created later without markers.
  sudo install -Dm644 /dev/null "$(cq_root /var/lib/omarchy/migrations/1789325478)"
  local pending
  pending=$(omarchy-migrate --status)
  [[ -z $pending ]] || cq_warn "pending Omarchy migrations after user setup: $(cut -f1,2 <<<"$pending" | paste -sd ' ')"
  cq_install_post_update_hook
}

cq_install_phase_login() {
  sudo install -d -m 755 "$(cq_root /var/lib/sddm)"
  printf '[Last]\nSession=omarchy.desktop\nUser=%s\n' "$USER" | sudo tee "$(cq_root /var/lib/sddm/state.conf)" >/dev/null
  sudo chown -R sddm:sddm "$(cq_root /var/lib/sddm)"
  # As omarchy-provision-owner does: encrypted installs log in automatically, because the
  # LUKS passphrase is the authentication boundary.
  if [[ $(cq_root_luks) == yes ]]; then
    sudo install -d -m 755 "$(cq_root /etc/sddm.conf.d)"
    printf '[Autologin]\nUser=%s\nSession=omarchy.desktop\n' "$USER" | sudo tee "$(cq_root /etc/sddm.conf.d/autologin.conf)" >/dev/null
  fi
  sudo systemctl enable sddm.service
}

cq_install_phase_rebuild() {
  sudo snapper -c root create --type single --description "cachyos-quattro pre-rebuild"
  sudo limine-mkinitcpio
  local out
  if ! out=$(sudo /usr/lib/cachyos-quattro/verify); then
    printf '%s\n' "$out"
    cq_log "Do not reboot. The pre-install backup is in $(cq_install_backup_dir); the snapper"
    cq_log "snapshots 'cachyos-quattro pre-install' and 'pre-rebuild' are in 'sudo snapper -c root list'."
    cq_die "the rebuilt system failed a protection check"
  fi
  printf '%s\n' "$out"
}

cq_install_phase_done() {
  # Everything install added explicitly, including packages the system steps installed;
  # uninstall removes this list minus pacman-Qqe.txt.
  pacman -Qqe >"$(cq_install_backup_dir)/installed-packages.txt"
  printf 'omarchy=%s\ncachyos-quattro=%s\ndate=%s\nbackup=%s\n' \
    "$(pacman -Q omarchy | cut -d' ' -f2)" "$(pacman -Q cachyos-quattro | cut -d' ' -f2)" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(cq_install_backup_dir)" | sudo tee "$(cq_lib_dir)/installed" >/dev/null
}

cq_install_describe() {
  case $1 in
  preflight) echo "check that this system is supported (changes nothing)" ;;
  backup) echo "snapshot, back up /boot, /etc and home configs, record baselines" ;;
  guard) echo "build and install the cachyos-quattro package (NoExtract drop-in, hooks, stubs, migration gate)" ;;
  pacman-conf) echo "add the NoExtract Include and Omarchy's stable repository, last, to /etc/pacman.conf" ;;
  keyring) echo "import and locally sign Omarchy's packaging key $CQ_OMARCHY_KEY" ;;
  packages) echo "install omarchy-keyring, omarchy and omarchy-settings, then check every protection" ;;
  base-packages) echo "install Omarchy's base packages, minus ledger/base-packages-exclude.txt" ;;
  system) echo "run Omarchy's reviewed system setup steps as root (ledger/install-steps.tsv)" ;;
  user) echo "copy /etc/skel into your home and run Omarchy's user setup" ;;
  login) echo "set SDDM to start the Omarchy session and enable it" ;;
  rebuild) echo "snapshot, rebuild the initramfs with CachyOS's tools, run every check" ;;
  done) echo "record the install in /var/lib/cachyos-quattro/installed" ;;
  esac
}

cmd_install() {
  local yes=0 phase
  while (($#)); do
    case $1 in
    --yes) yes=1 ;;
    *) cq_die "install: unknown option $1" ;;
    esac
    shift
  done
  sudo true || cq_die "install needs sudo"
  for phase in "${CQ_INSTALL_PHASES[@]}"; do
    if cq_phase_done "$phase"; then
      cq_log "== $phase: already done"
      continue
    fi
    cq_log "== $phase: $(cq_install_describe "$phase")"
    if ((!yes)) && ! cq_confirm "Run $phase?"; then
      cq_die "stopped before $phase; run 'cachyos-quattro install' again to continue"
    fi
    case $phase in
    preflight) cq_run_phase cmd_preflight ;;
    backup) cq_run_phase cmd_backup ;;
    *) cq_run_phase "cq_install_phase_${phase//-/_}" ;;
    esac
    if ((CQ_PHASE_RC != 0)); then
      case $phase in
      preflight) cq_die "preflight refused this system" ;;
      backup) cq_die "backup failed; nothing has been changed yet" ;;
      *) cq_die "$phase failed; fix the cause and run 'cachyos-quattro install' again to resume" ;;
      esac
    fi
    cq_phase_mark "$phase"
  done
  cq_ok "Omarchy is installed and every check passed. It is safe to reboot."
}
