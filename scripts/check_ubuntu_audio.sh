#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Auto-detect custom VERITURN_HOME if a .shim file or directory exists in the release root
if [[ -z "${VERITURN_HOME:-}" && -e "$RELEASE_ROOT/.shim" ]]; then
  export VERITURN_HOME="$RELEASE_ROOT"
fi

ROOT="${VERITURN_HOME:-$HOME/.veriturn}"

section() {
  printf '\n== %s ==\n' "$1"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

section "VeriTurn Ubuntu Audio Diagnostic"
echo "Install root: $ROOT"
echo "This script only inspects local audio, Bluetooth, and ADB readiness."

section "System"
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  echo "OS: ${PRETTY_NAME:-unknown}"
else
  echo "OS: unknown"
fi
echo "Kernel: $(uname -srmo)"
if have ldd; then
  ldd --version | head -n 1
else
  echo "ldd: missing"
fi

section "Required Commands"
for cmd in adb bluetoothctl pactl pw-cli pw-record pw-play; do
  if have "$cmd"; then
    echo "$cmd: present ($(command -v "$cmd"))"
  else
    echo "$cmd: missing"
  fi
done

section "PipeWire And PulseAudio Compatibility"
if have pactl; then
  pactl info 2>/dev/null | sed -n '1,12p' || echo "pactl info failed"
  echo
  echo "Input sources:"
  pactl list short sources 2>/dev/null || true
  echo
  echo "Output sinks:"
  pactl list short sinks 2>/dev/null || true
elif have pw-cli; then
  echo "pactl is unavailable; listing PipeWire nodes with pw-cli."
  pw-cli ls Node 2>/dev/null | sed -n '1,120p' || true
else
  echo "No pactl or pw-cli found. Install PipeWire/PulseAudio tools for detailed audio diagnostics."
fi

section "Bluetooth"
if have bluetoothctl; then
  bluetoothctl show 2>/dev/null || true
  echo
  echo "Paired devices:"
  bluetoothctl devices Paired 2>/dev/null || bluetoothctl devices 2>/dev/null || true
  echo
  echo "For HFP calls, BlueZ input/output call nodes usually appear only during an active phone call routed to this computer."
else
  echo "bluetoothctl is missing. Install bluez and enable Bluetooth before HFP testing."
fi

section "ADB"
if have adb; then
  adb devices -l 2>/dev/null || true
  echo "Authorize the phone when prompted, then rerun this diagnostic if the device is unauthorized."
else
  echo "adb is missing. Install Android platform tools before phone-control readiness checks."
fi

section "VeriTurn Release Paths"
for dir in "$ROOT/app" "$ROOT/runtime" "$ROOT/models" "$ROOT/db" "$ROOT/evidence"; do
  if [[ -d "$dir" ]]; then
    echo "$dir: present"
  else
    echo "$dir: missing"
  fi
done

section "Next Steps"
echo "Open VeriTurn with scripts/launch_veriturn.sh, then run Settings -> Setup Check."
echo "If Bluetooth call audio is missing, start an active test call and route phone audio to this computer before rerunning this script."
