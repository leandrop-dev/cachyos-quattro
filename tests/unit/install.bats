#!/usr/bin/env bats
# Single-quoted bodies are literal on purpose: they are file contents and stub scripts.
# shellcheck disable=SC2016

load helpers

setup() {
  export CQ_ROOT="$BATS_TEST_TMPDIR/root"
  export CQ_REPO="$BATS_TEST_DIRNAME/../.."
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$CQ_ROOT" "$HOME" "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nexec "$@"\n' >"$BATS_TEST_TMPDIR/bin/sudo"
  chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  # shellcheck source=lib/common.sh
  source "$CQ_REPO/lib/common.sh"
  # shellcheck source=lib/detect.sh
  source "$CQ_REPO/lib/detect.sh"
  # shellcheck source=lib/cmd-install.sh
  source "$CQ_REPO/lib/cmd-install.sh"

  INSTALL=$BATS_TEST_TMPDIR/install
  mkdir -p "$INSTALL"/{config,hardware,login,post-install}
  printf '# config\nrun_logged "$OMARCHY_INSTALL/config/a.sh"\nrun_logged "$OMARCHY_INSTALL/config/snapper.sh"\n' >"$INSTALL/config/all.sh"
  printf 'run_logged "$OMARCHY_INSTALL/hardware/b.sh"\n' >"$INSTALL/hardware/all.sh"
  printf 'run_logged "$OMARCHY_INSTALL/login/sddm.sh"\n' >"$INSTALL/login/all.sh"
  printf '\nrun_logged "$OMARCHY_INSTALL/post-install/pacman.sh"\n' >"$INSTALL/post-install/all.sh"
  STEPS=$BATS_TEST_TMPDIR/install-steps.tsv
  printf '# script\tverdict\treason\nconfig/a.sh\trun\tx\nconfig/snapper.sh\tskip\tx\nhardware/b.sh\trun\tx\nlogin/sddm.sh\trun\tx\npost-install/pacman.sh\tskip\tx\n' >"$STEPS"
}

# stub_phases: every phase only records that it ran.
stub_phases() {
  local phase
  cmd_preflight() { echo preflight >>"$HOME/phases.log"; }
  cmd_backup() { echo backup >>"$HOME/phases.log"; }
  for phase in "${CQ_INSTALL_PHASES[@]:2}"; do
    eval "cq_install_phase_${phase//-/_}() { echo $phase >>\"\$HOME/phases.log\"; }"
  done
}

@test "the step plan follows Omarchy's order with the ledger's verdicts" {
  run cq_install_plan_steps "$INSTALL" "$STEPS"
  [ "$status" -eq 0 ]
  [ "$output" = $'run\tconfig/a.sh\nskip\tconfig/snapper.sh\nrun\thardware/b.sh\nrun\tlogin/sddm.sh\nskip\tpost-install/pacman.sh' ]
}

@test "an install step the ledger has not reviewed stops the plan" {
  printf 'run_logged "$OMARCHY_INSTALL/hardware/new.sh"\n' >>"$INSTALL/hardware/all.sh"
  run cq_install_plan_steps "$INSTALL" "$STEPS"
  [ "$status" -eq 1 ]
  [[ $output == *"install step hardware/new.sh is not reviewed"* ]]
}

@test "a line other than run_logged in an all.sh stops the plan" {
  printf 'source "$OMARCHY_INSTALL/hardware/more.sh"\n' >>"$INSTALL/hardware/all.sh"
  run cq_install_plan_steps "$INSTALL" "$STEPS"
  [ "$status" -eq 1 ]
  [[ $output == *"unexpected line in hardware/all.sh"* ]]
}

@test "the shipped ledger reviews every step of Omarchy 4.0.6's installer" {
  # Built from the ledger itself: every reviewed script, in its own group's all.sh.
  local group
  for group in config hardware login post-install; do
    awk -F'\t' -v g="$group/" '!/^#/ && index($1, g) == 1 { printf "run_logged \"$OMARCHY_INSTALL/%s\"\n", $1 }' \
      "$CQ_REPO/ledger/install-steps.tsv" >"$INSTALL/$group/all.sh"
  done
  run cq_install_plan_steps "$INSTALL" "$CQ_REPO/ledger/install-steps.tsv"
  [ "$status" -eq 0 ]
  [ "$(grep -c . <<<"$output")" -eq 50 ]
  [ "$(grep -c '^skip' <<<"$output")" -eq 10 ]
}

@test "install runs every phase in order and marks each one" {
  stub_phases
  run cmd_install --yes
  [ "$status" -eq 0 ]
  [ "$(paste -sd ' ' "$HOME/phases.log")" = "${CQ_INSTALL_PHASES[*]}" ]
  for phase in "${CQ_INSTALL_PHASES[@]}"; do
    [ -e "$CQ_ROOT/var/lib/cachyos-quattro/phases/$phase" ]
  done
  [[ $output == *"safe to reboot"* ]]
}

@test "a second run skips the phases that are done" {
  stub_phases
  cmd_install --yes >/dev/null
  rm "$HOME/phases.log"
  run cmd_install --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/phases.log" ]
  [[ $output == *"== rebuild: already done"* ]]
}

@test "a failing phase is not marked, and the next run resumes there" {
  stub_phases
  cq_install_phase_system() { echo system >>"$HOME/phases.log"; return 1; }
  run cmd_install --yes
  [ "$status" -ne 0 ]
  [ ! -e "$CQ_ROOT/var/lib/cachyos-quattro/phases/system" ]
  [ -e "$CQ_ROOT/var/lib/cachyos-quattro/phases/base-packages" ]
  stub_phases
  rm "$HOME/phases.log"
  run cmd_install --yes
  [ "$status" -eq 0 ]
  [ "$(paste -sd ' ' "$HOME/phases.log")" = "system user login rebuild done" ]
}

@test "declining a phase stops before it" {
  stub_phases
  run cmd_install <<<$'y\nn'
  [ "$status" -eq 1 ]
  [[ $output == *"stopped before backup"* ]]
  [ "$(cat "$HOME/phases.log")" = preflight ]
}

@test "a command failing early in a phase fails the phase, even when its last command succeeds" {
  stub_phases
  cq_install_phase_base_packages() {
    false
    echo base-packages >>"$HOME/phases.log"
  }
  run cmd_install --yes
  [ "$status" -ne 0 ]
  [[ $output == *"base-packages failed"* ]]
  [ ! -e "$CQ_ROOT/var/lib/cachyos-quattro/phases/base-packages" ]
  run grep -qx base-packages "$HOME/phases.log"
  [ "$status" -eq 1 ]
}

@test "cq_pacman retries a failed transaction" {
  printf '#!/bin/bash\necho x >>"$HOME/pacman.calls"\n[[ $(wc -l <"$HOME/pacman.calls") -ge 2 ]]\n' >"$BATS_TEST_TMPDIR/bin/pacman"
  chmod +x "$BATS_TEST_TMPDIR/bin/pacman"
  sleep() { :; }
  run cq_pacman -S --needed foo
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$HOME/pacman.calls")" -eq 2 ]
}
