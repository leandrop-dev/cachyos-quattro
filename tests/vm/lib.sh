# shellcheck shell=bash
# Shared helpers for the QEMU/OVMF test harness. Sourced, not executed.
# Variables below are read by the scripts that source this file.
# shellcheck disable=SC2034

VM_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$VM_DIR/../.." && pwd)
IMAGES_DIR="$VM_DIR/images"
RUN_DIR="$VM_DIR/run"
OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
OVMF_VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd
SSH_KEY="$IMAGES_DIR/id_ed25519"
VM_USER=tester
LUKS_PASSPHRASE=cq-test-passphrase

vm_die() {
  echo "vm: $*" >&2
  exit 2
}

vm_log() {
  echo "vm: $*" >&2
}

# vm_qemu_args <disk> <vars> <ssh-port>: common machine definition.
vm_qemu_args() {
  printf '%s\n' \
    -enable-kvm -machine q35 -cpu host -smp 4 -m 4096 \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=$2" \
    -drive "if=virtio,format=qcow2,file=$1" \
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$3-:22"
}

# vm_free_port: print a TCP port on 127.0.0.1 with no listener.
vm_free_port() {
  local port
  for _ in {1..50}; do
    port=$(shuf -i 20000-29999 -n 1)
    ss -Hltn "sport = :$port" | grep -q . || {
      echo "$port"
      return 0
    }
  done
  vm_die "no free TCP port found"
}

# vm_ssh <port> <command...>: run a command on the guest as $VM_USER.
# The guest's login shell is fish (the CachyOS default), so the command must be
# valid fish; send anything longer to `bash -s` on stdin.
vm_ssh() {
  local port=$1
  shift
  ssh -i "$SSH_KEY" -p "$port" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -o ConnectTimeout=5 -o BatchMode=yes \
    "$VM_USER@127.0.0.1" "$@"
}

# vm_wait_ssh <port> <timeout-seconds>: succeed once the guest accepts SSH.
vm_wait_ssh() {
  local port=$1 deadline=$((SECONDS + $2))
  while ((SECONDS < deadline)); do
    vm_ssh "$port" true && return 0
    sleep 3
  done
  return 1
}

# vm_qcodes <string>: print the QMP qcode for each character, one per line.
# Only the characters the harness types are supported: a-z, 0-9 and '-'.
vm_qcodes() {
  local s=$1 i c
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [a-z0-9]) echo "$c" ;;
      -) echo minus ;;
      *) vm_die "vm_qcodes: unsupported character '$c'" ;;
    esac
  done
}

# vm_qmp <socket> <json...>: send QMP commands after the capabilities handshake.
vm_qmp() {
  local sock=$1
  shift
  {
    echo '{"execute":"qmp_capabilities"}'
    printf '%s\n' "$@"
    sleep 0.5
  } | socat - "UNIX-CONNECT:$sock" >/dev/null
}

# vm_stop <socket> <pidfile>: ask QEMU to quit, then kill it if it is still
# running after 10 s. QEMU closes the socket while socat is still reading, so
# socat's exit status says nothing about whether the quit worked.
vm_stop() {
  local sock=$1 pid
  pid=$(cat "$2")
  [[ -d /proc/$pid ]] || return 0
  vm_qmp "$sock" '{"execute":"quit"}' || true
  for _ in {1..20}; do
    [[ -d /proc/$pid ]] || return 0
    sleep 0.5
  done
  vm_log "QEMU $pid ignored quit; killing it"
  kill "$pid"
}

# vm_type <socket> <string>: type a string followed by Enter on the guest keyboard.
vm_type() {
  local sock=$1 code cmds=()
  while read -r code; do
    cmds+=("{\"execute\":\"send-key\",\"arguments\":{\"keys\":[{\"type\":\"qcode\",\"data\":\"$code\"}]}}")
  done < <(vm_qcodes "$2")
  cmds+=('{"execute":"send-key","arguments":{"keys":[{"type":"qcode","data":"ret"}]}}')
  vm_qmp "$sock" "${cmds[@]}"
}

# vm_overlay_boot <image> <label>: boot a headless copy-on-write overlay of a
# sealed golden image and wait until it answers SSH. Sets port, qmp, overlay,
# vars, pidfile, sockdir and run_id for the caller and for vm_overlay_cleanup.
vm_overlay_boot() {
  local image=$1 golden="$IMAGES_DIR/$1.qcow2" args
  [[ -f $golden ]] || vm_die "no golden image $golden; see docs/testing.md"
  [[ ! -w $golden ]] || vm_die "$golden is not sealed; run 'golden.sh seal $image'"
  [[ -f $SSH_KEY ]] || vm_die "no harness key $SSH_KEY"

  run_id="$image-$2-$(date -u +%Y%m%dT%H%M%S)"
  mkdir -p "$RUN_DIR"
  overlay="$RUN_DIR/$run_id.qcow2"
  vars="$RUN_DIR/$run_id.vars.fd"
  pidfile="$RUN_DIR/$run_id.pid"
  # UNIX socket paths must stay under 108 bytes, so the QMP socket lives in a
  # short runtime directory rather than next to the overlay.
  sockdir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/cq-vm.XXXXXX")
  qmp="$sockdir/qmp"
  port=$(vm_free_port)

  qemu-img create -q -f qcow2 -b "$golden" -F qcow2 "$overlay"
  cp "$IMAGES_DIR/$image.vars.fd" "$vars"
  chmod u+w "$vars"

  mapfile -t args < <(vm_qemu_args "$overlay" "$vars" "$port")
  qemu-system-x86_64 "${args[@]}" -display none -vga std \
    -serial "file:$RUN_DIR/$run_id.serial.log" \
    -qmp "unix:$qmp,server,nowait" -pidfile "$pidfile" -daemonize

  vm_log "booting $image (ssh port $port)"
  vm_unlock_and_wait "$qmp" "$port" "$image" || vm_die "guest did not come up"
}

# vm_overlay_cleanup <passed>: stop the guest; delete the overlay when the run
# passed (1) unless KEEP=1, otherwise keep it for inspection.
vm_overlay_cleanup() {
  [[ -n ${run_id:-} ]] || return 0
  [[ ! -f $pidfile ]] || vm_stop "$qmp" "$pidfile"
  rm -rf "$sockdir"
  if (($1)) && [[ ${KEEP:-0} != 1 ]]; then
    rm -f "$overlay" "$vars" "$pidfile" "$RUN_DIR/$run_id.serial.log"
  else
    vm_log "kept $overlay for inspection"
  fi
}

# vm_is_luks <image>: images named *-luks* have an encrypted root.
vm_is_luks() {
  [[ $1 == *luks* ]]
}

# vm_unlock_and_wait <socket> <port> <image>: on LUKS images, type the
# passphrase until SSH answers; on plain images, just wait for SSH.
vm_unlock_and_wait() {
  local sock=$1 port=$2 image=$3 attempt
  if ! vm_is_luks "$image"; then
    vm_wait_ssh "$port" 180
    return
  fi
  for attempt in 1 2 3 4; do
    sleep 25
    vm_log "typing LUKS passphrase (attempt $attempt)"
    vm_type "$sock" "$LUKS_PASSPHRASE"
    vm_wait_ssh "$port" 60 && return 0
  done
  return 1
}
