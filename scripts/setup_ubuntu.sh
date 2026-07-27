#!/usr/bin/env bash
set -euo pipefail

VERSION=""
VERIFY_ONLY=0
SKIP_MODELS=0
GPU_MODE="auto"   # auto | cpu | cuda
REPO="${VERITURN_RELEASE_REPO:-rupinrd3/VeriTurn}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/setup_ubuntu.sh [options]
  scripts/setup_ubuntu.sh --version vX.Y.Z [options]
  scripts/setup_ubuntu.sh --upgrade vX.Y.Z [options]
  scripts/setup_ubuntu.sh --verify
  scripts/setup_ubuntu.sh --help

Options:
  --version vX.Y.Z
                 Install this exact release. If omitted, the script uses
                 APP_VERSION / RELEASE_MANIFEST.json from the git-pulled
                 release repository.
  --skip-models   Do not download or repair local runtime models.
  --force-cpu     Install the CPU-only runtime bundle even if an NVIDIA GPU is detected.
  --force-cuda    Install the CUDA runtime overlay even if no NVIDIA GPU is detected
                  (the app will still run on CPU if the GPU/driver is not usable at runtime).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|--upgrade)
      VERSION="${2:-}"
      shift 2
      ;;
    --version=*|--upgrade=*)
      VERSION="${1#*=}"
      shift
      ;;
    --verify)
      VERIFY_ONLY=1
      shift
      ;;
    --skip-models)
      SKIP_MODELS=1
      shift
      ;;
    --force-cpu)
      GPU_MODE="cpu"
      shift
      ;;
    --force-cuda)
      GPU_MODE="cuda"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Auto-detect custom VERITURN_HOME if a .shim file or directory exists in the release root
if [[ -z "${VERITURN_HOME:-}" && -e "$RELEASE_ROOT/.shim" ]]; then
  export VERITURN_HOME="$RELEASE_ROOT"
fi

ROOT="${VERITURN_HOME:-$HOME/.veriturn}"
DOWNLOADS="$ROOT/downloads"
STAGING="$ROOT/staging"

mkdir -p "$ROOT"/{app,runtime,models/llm,models/stt,models/tts,models/translation,db,evidence,backups,downloads,staging,logs}

echo "VeriTurn Studio release installer"
echo "Install root: $ROOT"
echo "Release repo: $REPO"
echo "Use of this software is governed by $RELEASE_ROOT/LICENSE.txt."

# Auto-detect version from the release repository files if not explicitly provided
if [[ -z "$VERSION" ]]; then
  if [[ -f "$RELEASE_ROOT/APP_VERSION" ]]; then
    VERSION="$(tr -d '[:space:]' < "$RELEASE_ROOT/APP_VERSION")"
  elif [[ -f "$RELEASE_ROOT/RELEASE_MANIFEST.json" ]]; then
    VERSION="$(python3 - "$RELEASE_ROOT/RELEASE_MANIFEST.json" <<'PY'
import json, pathlib, sys
try:
    manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    print(manifest.get("release_version", ""))
except Exception:
    pass
PY
)"
  fi
fi

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  MANIFEST_PATH="$RELEASE_ROOT/RELEASE_MANIFEST.json"
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    MANIFEST_PATH="$ROOT/app/RELEASE_MANIFEST.json"
  fi

  ASSET_DIR="$RELEASE_ROOT"
  if [[ -n "${VERSION:-}" ]]; then
    APP_ASSET_NAME=""
    if [[ -f "$MANIFEST_PATH" ]]; then
      APP_ASSET_NAME="$(python3 - "$MANIFEST_PATH" <<'PY'
import json, pathlib, sys
try:
    manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    print(manifest.get("app", {}).get("asset", ""))
except Exception:
    pass
PY
)"
    fi

    if [[ -n "$APP_ASSET_NAME" ]]; then
      if [[ -f "$ROOT/downloads/$VERSION/$APP_ASSET_NAME" ]]; then
        ASSET_DIR="$ROOT/downloads/$VERSION"
      elif [[ -f "$RELEASE_ROOT/$APP_ASSET_NAME" ]]; then
        ASSET_DIR="$RELEASE_ROOT"
      fi
    fi
  fi

  if [[ -f "$MANIFEST_PATH" ]]; then
    "$SCRIPT_DIR/verify_release_assets.sh" "$MANIFEST_PATH" "$ASSET_DIR"
  else
    echo "Error: Release manifest not found." >&2
    exit 1
  fi
  exit 0
fi

if [[ -z "$VERSION" ]]; then
  echo "Error: Release version could not be auto-detected, and --version vX.Y.Z was not provided." >&2
  exit 2
fi

# ──────────────────────────────────────────────────────────────────────────────
#  Required commands
# ──────────────────────────────────────────────────────────────────────────────
need_cmd() {
  local cmd="$1"
  local guidance="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd is required. $guidance" >&2
    exit 1
  fi
}

warn_cmd() {
  local cmd="$1"
  local guidance="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Warning: $cmd is missing. $guidance"
    return 1
  fi
  return 0
}

check_component() {
  local name="$1"
  local result="$2"   # ok | miss | warn | skip
  local hint="${3:-}"
  case "$result" in
    ok)   printf "  [OK]    %s\n" "$name" ;;
    warn) printf "  [WARN]  %-44s -> %s\n" "$name" "$hint" ;;
    skip) printf "  [SKIP]  %s\n" "$name" ;;
    miss) printf "  [MISS]  %-44s -> %s\n" "$name" "$hint" ;;
  esac
}

model_file() {
  [[ -f "$ROOT/models/$1" ]]
}

model_dir_nonempty() {
  [[ -d "$ROOT/models/$1" ]] && [[ -n "$(find "$ROOT/models/$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

nemotron_model_ready() {
  model_file "stt/nemotron-3.5-asr-streaming-0.6b-onnx/encoder.onnx" &&
    model_file "stt/nemotron-3.5-asr-streaming-0.6b-onnx/encoder.onnx.data" &&
    model_file "stt/nemotron-3.5-asr-streaming-0.6b-onnx/tokenizer.model" &&
    { model_file "stt/nemotron-3.5-asr-streaming-0.6b-onnx/decoder_joint.onnx" ||
      model_file "stt/nemotron-3.5-asr-streaming-0.6b-onnx/decoder.onnx"; }
}

sherpa_stt_ready() {
  model_file "stt/sherpa-onnx-whisper-large-v3/large-v3-encoder.int8.onnx" &&
    model_file "stt/sherpa-onnx-whisper-large-v3/large-v3-decoder.int8.onnx" &&
    model_file "stt/sherpa-onnx-whisper-large-v3/large-v3-tokens.txt"
}

piper_voice_ready() {
  local base="$1"
  model_file "tts/${base}.onnx" && model_file "tts/${base}.onnx.json"
}

mms_voice_ready() {
  local code="$1"
  model_file "tts/sherpa-vits-mms/vits-mms-${code}.onnx" &&
    model_file "tts/sherpa-vits-mms/tokens-${code}.txt"
}

kokoro_ready() {
  model_file "tts/kokoro-82m-v1.0.onnx" &&
    model_file "tts/tokens.txt" &&
    model_file "tts/voices.bin" &&
    model_dir_nonempty "tts/espeak-ng-data"
}

translation_ct2_ready() {
  model_file "translation/indictrans2-indic-en-ct2/model.bin" &&
    model_file "translation/indictrans2-indic-en-ct2/source_vocabulary.txt" &&
    model_file "translation/indictrans2-indic-en-ct2/target_vocabulary.txt"
}

gguf_count() {
  find "$ROOT/models/llm" -type f -name "*.gguf" 2>/dev/null | wc -l | tr -d ' '
}

runtime_file() {
  [[ -f "$ROOT/runtime/bin/$1" || -f "$ROOT/runtime/lib/$1" ]]
}

runtime_executable_path() {
  local name="$1"
  if [[ -x "$ROOT/runtime/bin/$name" ]]; then
    printf '%s\n' "$ROOT/runtime/bin/$name"
  elif [[ -x "$ROOT/runtime/lib/$name" ]]; then
    printf '%s\n' "$ROOT/runtime/lib/$name"
  else
    return 1
  fi
}

runtime_executable_ready() {
  local name="$1"
  local exe
  exe="$(runtime_executable_path "$name" 2>/dev/null)" || return 1
  if ! [[ -x "$exe" ]]; then
    return 1
  fi
  if command -v ldd >/dev/null 2>&1; then
    if LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$exe" 2>/dev/null | grep -q "not found"; then
      return 1
    fi
  fi
  return 0
}

runtime_executable_detail() {
  local name="$1"
  local exe
  exe="$(runtime_executable_path "$name" 2>/dev/null)" || {
    printf 'missing from runtime/bin or runtime/lib'
    return 0
  }
  if command -v ldd >/dev/null 2>&1 &&
      LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$exe" 2>/dev/null | grep -q "not found"; then
    printf 'binary exists but shared libraries are missing; reinstall the runtime asset'
    return 0
  fi
  printf '%s' "$exe"
}

app_binary_ready() {
  local exe="$ROOT/app/bin/veriturn-studio"
  [[ -x "$exe" ]] || return 1
  if command -v ldd >/dev/null 2>&1; then
    ldd "$exe" 2>/dev/null | grep -q "not found" && return 1
  fi
  return 0
}

read_json_field_from_file() {
  local file="$1"
  local path="$2"
  python3 - "$file" "$path" <<'PY'
import json
import pathlib
import sys

try:
    value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    for key in sys.argv[2].split("."):
        value = value.get(key, {}) if isinstance(value, dict) else {}
    print(value if isinstance(value, str) else "")
except Exception:
    pass
PY
}

write_installed_asset_state() {
  local manifest="$1"
  local destination="$ROOT/app/INSTALLED_ASSETS.json"
  python3 - "$manifest" "$destination" "$GPU_MODE" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
runtime = manifest.get("runtime_tools", {})
state = {
    "release_version": manifest.get("release_version", ""),
    "app": manifest.get("app", {}),
    "runtime_tools": {
        "cpu": runtime.get("cpu", {}) if isinstance(runtime.get("cpu"), dict) else {},
        "cuda": runtime.get("cuda", {}) if isinstance(runtime.get("cuda"), dict) else {},
        "installed_variant": sys.argv[3],
    },
}
pathlib.Path(sys.argv[2]).write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
PY
}

installed_assets_current() {
  local target_manifest="$1"
  local state="$ROOT/app/INSTALLED_ASSETS.json"

  [[ -f "$target_manifest" ]] || return 1
  [[ -f "$state" ]] || return 1
  app_binary_ready || return 1
  runtime_executable_ready "llama-server" || return 1
  runtime_executable_ready "whisper-server" || return 1
  runtime_executable_ready "piper-tts-server" || return 1

  python3 - "$target_manifest" "$state" "$GPU_MODE" <<'PY'
import json
import pathlib
import sys

target = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
state = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
gpu_mode = sys.argv[3]

def field(doc, dotted):
    value = doc
    for key in dotted.split("."):
        value = value.get(key, {}) if isinstance(value, dict) else {}
    return value if isinstance(value, str) else ""

required = [
    "release_version",
    "app.asset",
    "app.sha256",
    "runtime_tools.cpu.asset",
    "runtime_tools.cpu.sha256",
]
if gpu_mode == "cuda" and field(target, "runtime_tools.cuda.asset"):
    required.extend(["runtime_tools.cuda.asset", "runtime_tools.cuda.sha256"])

for key in required:
    if field(target, key) != field(state, key):
        raise SystemExit(1)

if field(state, "runtime_tools.installed_variant") != gpu_mode:
    raise SystemExit(1)
PY
}

hf_ready() {
  command -v hf >/dev/null 2>&1 && hf auth whoami >/dev/null 2>&1
}

run_model_downloads() {
  echo
  echo "== Local model downloads and verification =="
  if [[ "$SKIP_MODELS" -eq 1 ]]; then
    echo "Skipped (--skip-models passed). Run: $RELEASE_ROOT/scripts/download_default_models.sh"
    return 0
  fi
  if "$SCRIPT_DIR/download_default_models.sh"; then
    echo "Model helper completed."
  else
    echo "Warning: one or more model downloads failed. The summary below shows remaining gaps."
    echo "Re-run after fixing network/Hugging Face access: $RELEASE_ROOT/scripts/download_default_models.sh"
  fi
}

print_final_summary() {
  local title="${1:-Final status summary}"
  echo
  echo "== $title =="
  echo "Install root: $ROOT"
  echo "Release version: $VERSION"
  echo "Runtime variant: ${GPU_MODE:-unknown}"
  echo "OS: ${OS_PRETTY:-unknown}   glibc: $(ldd --version 2>/dev/null | head -n 1 || echo unknown)"

  echo
  echo "App and packaged runtime"
  app_binary_ready && check_component "App binary" ok || check_component "App binary" miss "missing or dependency-broken; install/download the app asset again"
  runtime_executable_ready "llama-server" && check_component "llama-server runtime" ok || check_component "llama-server runtime" miss "$(runtime_executable_detail "llama-server")"
  runtime_executable_ready "whisper-server" && check_component "whisper-server runtime" ok || check_component "whisper-server runtime" miss "$(runtime_executable_detail "whisper-server")"
  runtime_executable_ready "piper" && check_component "piper CLI runtime" ok || check_component "piper CLI runtime" miss "$(runtime_executable_detail "piper")"
  runtime_executable_ready "piper-tts-server" && check_component "piper-tts-server runtime" ok || check_component "piper-tts-server runtime" miss "$(runtime_executable_detail "piper-tts-server")"
  runtime_executable_ready "sherpa-onnx-offline" && check_component "sherpa STT runtime" ok || check_component "sherpa STT runtime" miss "$(runtime_executable_detail "sherpa-onnx-offline")"
  runtime_executable_ready "sherpa-onnx-offline-tts" && check_component "sherpa TTS runtime" ok || check_component "sherpa TTS runtime" miss "$(runtime_executable_detail "sherpa-onnx-offline-tts")"
  runtime_executable_ready "veriturn-nemotron-stt" && check_component "Nemotron STT adapter" ok || check_component "Nemotron STT adapter" miss "$(runtime_executable_detail "veriturn-nemotron-stt")"
  runtime_executable_ready "veriturn-ct2-translate" && check_component "CT2 translation runtime" ok || check_component "CT2 translation runtime" warn "only needed when CT2 translation is enabled; reinstall runtime asset if selected"
  if find "$ROOT/runtime/lib" -maxdepth 1 -name 'libggml-cuda.so*' -print -quit 2>/dev/null | grep -q .; then
    check_component "CUDA runtime overlay" ok
  else
    check_component "CUDA runtime overlay" skip
  fi

  echo
  echo "Default local models"
  model_file "stt/ggml-small.en.bin" && check_component "Whisper small.en STT fallback" ok || check_component "Whisper small.en STT fallback" miss "run scripts/download_default_models.sh"
  model_file "stt/ggml-indic-whisper-medium-f16.bin" && check_component "IndicWhisper GGUF fallback" ok || check_component "IndicWhisper GGUF fallback" warn "optional fallback; re-run model helper if selected in Settings"
  nemotron_model_ready && check_component "Nemotron ONNX en/hi STT model" ok || check_component "Nemotron ONNX en/hi STT model" miss "required for nemotron_onnx; run scripts/download_default_models.sh"
  sherpa_stt_ready && check_component "sherpa Whisper large-v3 STT model" ok || check_component "sherpa Whisper large-v3 STT model" miss "required for sherpa_onnx; run scripts/download_default_models.sh"
  piper_voice_ready "en_US-lessac-high" && check_component "Piper voice: en_US-lessac" ok || check_component "Piper voice: en_US-lessac" miss "run scripts/download_default_models.sh"
  piper_voice_ready "en_US-ryan-high" && check_component "Piper voice: en_US-ryan" ok || check_component "Piper voice: en_US-ryan" miss "run scripts/download_default_models.sh"
  piper_voice_ready "hi_IN-priyamvada-medium" && check_component "Piper voice: hi_IN-priyamvada" ok || check_component "Piper voice: hi_IN-priyamvada" miss "run scripts/download_default_models.sh"
  piper_voice_ready "hi_IN-rohan-medium" && check_component "Piper voice: hi_IN-rohan" ok || check_component "Piper voice: hi_IN-rohan" miss "run scripts/download_default_models.sh"
  mms_voice_ready "ben" && mms_voice_ready "mar" && mms_voice_ready "tel" && mms_voice_ready "tam" && mms_voice_ready "guj" && mms_voice_ready "kan" &&
    check_component "sherpa MMS Indic TTS voices" ok || check_component "sherpa MMS Indic TTS voices" miss "required for local Bengali/Marathi/Telugu/Tamil/Gujarati/Kannada TTS"
  kokoro_ready && check_component "Kokoro English TTS assets" ok || check_component "Kokoro English TTS assets" warn "optional voice; re-run model helper if selected"
  if [[ "$(gguf_count)" -gt 0 ]]; then
    check_component "Local LLM GGUF model(s)" ok
    find "$ROOT/models/llm" -maxdepth 1 -type f -name "*.gguf" 2>/dev/null | while read -r f; do
      printf "          %s  %s\n" "$(du -h "$f" 2>/dev/null | cut -f1 || echo '?')" "$(basename "$f")"
    done
  else
    check_component "Local LLM GGUF model(s)" miss "download/place a .gguf or select Gemini/NVIDIA NIM in Settings"
  fi
  translation_ct2_ready && check_component "CT2/IndicTrans2 translation model" ok || check_component "CT2/IndicTrans2 translation model" warn "only needed when offline CT2 translation is enabled"

  echo
  echo "Host readiness"
  if systemctl is-active bluetooth >/dev/null 2>&1; then check_component "Bluetooth service" ok; else check_component "Bluetooth service" miss "sudo systemctl start bluetooth && sudo systemctl enable bluetooth"; fi
  if systemctl --user is-active pipewire >/dev/null 2>&1; then check_component "PipeWire service" ok; else check_component "PipeWire service" miss "systemctl --user start pipewire"; fi
  if systemctl --user is-active wireplumber >/dev/null 2>&1; then check_component "WirePlumber service" ok; else check_component "WirePlumber service" miss "systemctl --user start wireplumber"; fi
  command -v adb >/dev/null 2>&1 && check_component "ADB" ok || check_component "ADB" miss "sudo apt install -y adb"
  if command -v bluetoothctl >/dev/null 2>&1; then
    paired_count="$(bluetoothctl devices Paired 2>/dev/null | wc -l || echo 0)"
    if [[ "${paired_count:-0}" -gt 0 ]]; then
      check_component "Paired Bluetooth devices" ok
    else
      check_component "Paired Bluetooth devices" warn "pair the Android test phone and enable Calls/Phone audio"
    fi
  else
    check_component "bluetoothctl" miss "sudo apt install -y bluez"
  fi
  wp_conf_found=false
  [[ -n "$(find "$HOME/.config/wireplumber/wireplumber.conf.d" -maxdepth 1 -name '*.conf' 2>/dev/null | head -1)" ]] && wp_conf_found=true
  [[ -n "$(find "$HOME/.config/wireplumber/bluetooth.lua.d" -maxdepth 1 -name '*.lua' 2>/dev/null | head -1)" ]] && wp_conf_found=true
  if $wp_conf_found; then
    check_component "WirePlumber Bluetooth HFP config" ok
  else
    check_component "WirePlumber Bluetooth HFP config" miss "re-run setup or create HFP role config before live calls"
  fi
  if command -v adb >/dev/null 2>&1; then
    adb_devices="$(adb devices 2>/dev/null | grep -v "List of devices" | grep -c "device$" || true)"
    if [[ "${adb_devices:-0}" -ge 1 ]]; then
      check_component "Authorized ADB device" ok
    else
      check_component "Authorized ADB device" warn "connect phone, enable USB debugging, and approve the prompt"
    fi
  fi
  hf_ready && check_component "Hugging Face CLI/auth" ok || check_component "Hugging Face CLI/auth" warn "needed only for gated LLM/translation downloads"
  if dpkg-query -W -f='${Status}' fonts-noto-extra 2>/dev/null | grep -q "install ok installed"; then
    check_component "Noto Indic fonts" ok
  else
    check_component "Noto Indic fonts" miss "sudo apt install -y fonts-noto fonts-noto-core fonts-noto-ui-core fonts-noto-extra"
  fi
  [[ -f "$ROOT/.env" ]] && check_component ".env API key template" ok || check_component ".env API key template" miss "re-run installer"
  for key in GEMINI_API_KEY NVIDIA_API_KEY SARVAM_API_KEY GNANI_API_KEY; do
    if grep -Eq "^${key}=.+" "$ROOT/.env" 2>/dev/null; then
      check_component "$key" ok
    else
      check_component "$key" skip
    fi
  done

  echo
  echo "Agentic AI mode (VOIP; optional — only required for Agentic mode)"
  [[ -x "$ROOT/runtime/voice-runner/linux-x64/run-voice-runner.sh" ]] && check_component "Bundled voice-runner" ok || check_component "Bundled voice-runner" miss "re-run installer to repair the runtime bundle"
  command -v cloudflared >/dev/null 2>&1 && check_component "cloudflared executable" ok || check_component "cloudflared executable" miss "see Agentic AI mode guidance above"
  _agentic_ports_ok=true
  for _p in 8090 8091 8092; do
    if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -qE ":${_p}\b"; then _agentic_ports_ok=false; fi
  done
  $_agentic_ports_ok && check_component "Agentic loopback ports 8090-8092 free" ok || check_component "Agentic loopback ports 8090-8092 free" miss "stop the conflicting local process"
  for key in TWILIO_ACCOUNT_SID PLIVO_AUTH_ID; do
    if grep -Eq "^${key}=.+" "$ROOT/.env" 2>/dev/null; then
      check_component "$key" ok
    else
      check_component "$key" skip
    fi
  done

  echo
  echo "Next steps"
  echo "  Launch: $RELEASE_ROOT/scripts/launch_veriturn.sh"
  echo "  Audio diagnostics: $RELEASE_ROOT/scripts/check_ubuntu_audio.sh"
  echo "  Model repair/retry: $RELEASE_ROOT/scripts/download_default_models.sh"
  echo "  Agentic VOIP diagnostic (non-dialing): $RELEASE_ROOT/scripts/check_agentic_voip.sh"
  echo "  In-app: Settings -> Global Health Check"
}

need_cmd python3 "Install python3 with your Ubuntu package manager."
need_cmd tar "Install tar with your Ubuntu package manager."
need_cmd sha256sum "Install coreutils with your Ubuntu package manager."
need_cmd ldd "Install libc-bin with your Ubuntu package manager."
need_cmd gh "Install GitHub CLI, then run: gh auth login --hostname github.com"
warn_cmd wget "Install wget so the model helper can download runtime models." || true
warn_cmd curl "Install curl for provider diagnostics and local STT upload checks." || true

echo
echo "== Runtime OS packages =="
echo "VeriTurn's release binaries do not require build tooling, but do need these"
echo "runtime packages for phone control, call audio, and Indic script rendering:"
echo
echo "    sudo apt update"
echo "    sudo apt install -y adb bluez pipewire wireplumber \\"
echo "      fonts-noto fonts-noto-core fonts-noto-ui-core fonts-noto-extra"
echo
warn_cmd adb "Install Android platform tools before phone-control readiness checks." || true
warn_cmd bluetoothctl "Install bluez before Bluetooth HFP readiness checks." || true
if ! command -v pactl >/dev/null 2>&1 && ! command -v pw-cli >/dev/null 2>&1; then
  echo "Warning: pactl/pw-cli missing. Install PipeWire/PulseAudio tools for audio diagnostics."
fi
if dpkg-query -W -f='${Status}' fonts-noto-extra 2>/dev/null | grep -q "install ok installed"; then
  echo "Noto fonts (including extras) are installed."
else
  echo "Warning: fonts-noto-extra not installed — Bengali/Devanagari/Telugu/etc. may render as boxes in the transcript."
fi

echo
echo "== Agentic AI mode (VOIP): cloudflared =="
echo "Agentic AI mode places test calls over Twilio/Plivo through a locally managed"
echo "Cloudflare Tunnel. The voice-runner itself is already bundled with this release"
echo "(a self-contained Python environment under \$HOME/.veriturn/runtime/voice-runner) —"
echo "only cloudflared needs separate installation. Skip this if you only use Human mode."
echo
if command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared found: $(command -v cloudflared)"
else
  echo "cloudflared not found. Install one of:"
  echo
  echo "    # Option A — apt repo (recommended, requires sudo)"
  echo "    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null"
  echo "    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs 2>/dev/null || echo any) main' | sudo tee /etc/apt/sources.list.d/cloudflared.list"
  echo "    sudo apt update && sudo apt install -y cloudflared"
  echo
  ARCH_CF="$(uname -m)"
  case "$ARCH_CF" in
    x86_64) CF_ARCH="amd64" ;;
    aarch64|arm64) CF_ARCH="arm64" ;;
    *) CF_ARCH="" ;;
  esac
  if [[ -n "$CF_ARCH" ]]; then
    echo "    # Option B — direct binary, no sudo (installs to ~/.local/bin/cloudflared)"
    echo "    curl -L -o ~/.local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
    echo "    chmod +x ~/.local/bin/cloudflared"
  fi
  echo
  echo "Then set the cloudflared executable path, tunnel name, and config path under Settings > Agentic VOIP."
fi
echo
echo "== Public tunnel: Quick (default, zero cost) vs Named (optional) =="
echo "A) Quick Tunnel — default / zero cost (recommended for lab live dials)"
echo "   No domain, no cloudflared login, no VERITURN_PUBLIC_BASE_URL."
echo "   After install, every app launch:"
echo "     Settings tunnel mode = Quick → Setup Checks: Start runner → Start free Quick Tunnel"
echo "   URL is https://*.trycloudflare.com (usually changes each start; re-arm after new URL)."
echo
echo "B) Named tunnel — optional stable hostname (requires a domain on Cloudflare)"
echo "     cloudflared tunnel login"
echo "     cloudflared tunnel create veriturn-voice"
echo "     cloudflared tunnel route dns veriturn-voice agentic-voice.YOUR_DOMAIN"
echo "     VERITURN_PUBLIC_BASE_URL=https://agentic-voice.YOUR_DOMAIN"
echo "     Settings: tunnel_mode=named + Scaffold tunnel config"
echo
if command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared is available for Quick Tunnel without further login."
else
  echo "Install cloudflared above before starting a Quick Tunnel from the app."
fi
echo
echo "Configure Twilio/Plivo credentials in \$HOME/.veriturn/.env (below) and run"
echo "  $RELEASE_ROOT/scripts/check_agentic_voip.sh   (non-dialing readiness diagnostic)"

# ──────────────────────────────────────────────────────────────────────────────
#  GPU detection (for the optional CUDA runtime overlay)
# ──────────────────────────────────────────────────────────────────────────────
detect_gpu() {
  command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1
}

case "$GPU_MODE" in
  auto)
    if detect_gpu; then
      echo "NVIDIA GPU detected ($(nvidia-smi -L 2>/dev/null | head -n 1)); will install the CUDA runtime overlay."
      GPU_MODE="cuda"
    else
      echo "No usable NVIDIA GPU detected (nvidia-smi missing or no device); installing CPU-only runtime."
      GPU_MODE="cpu"
    fi
    ;;
  cpu)
    echo "GPU auto-detection overridden: installing CPU-only runtime (--force-cpu)."
    ;;
  cuda)
    if ! detect_gpu; then
      echo "Warning: --force-cuda passed but no usable NVIDIA GPU/driver was detected. Installing the CUDA overlay anyway; the app will fail over to CPU at runtime if the GPU is unusable."
    fi
    echo "Installing the CUDA runtime overlay (--force-cuda)."
    ;;
esac

ARCH="$(uname -m)"
if [[ "$ARCH" != "x86_64" ]]; then
  echo "Unsupported architecture: $ARCH. This release expects Linux x86_64." >&2
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  OS_PRETTY="$(grep -E '^PRETTY_NAME=' /etc/os-release | head -n 1 | cut -d= -f2- | tr -d '"' || true)"
  OS_ID="$(grep -E '^ID=' /etc/os-release | head -n 1 | cut -d= -f2- | tr -d '"' || true)"
  OS_VERSION_ID="$(grep -E '^VERSION_ID=' /etc/os-release | head -n 1 | cut -d= -f2- | tr -d '"' || true)"
  echo "OS: ${OS_PRETTY:-unknown}"
  if [[ "${OS_ID:-}" == "ubuntu" ]] && [[ "$(printf '%s\n%s\n' "22.04" "${OS_VERSION_ID:-0}" | sort -V | head -n 1)" != "22.04" ]]; then
    echo "Ubuntu ${OS_VERSION_ID:-unknown} is below the supported baseline 22.04." >&2
    exit 1
  fi
else
  echo "Warning: /etc/os-release is not readable; OS support could not be confirmed."
fi
ldd --version | head -n 1 || true

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login --hostname github.com" >&2
  exit 1
fi

if [[ ! -f "$ROOT/.env" ]]; then
  cat > "$ROOT/.env" <<'ENV'
# VeriTurn Studio — API Keys
# Read at startup. Never commit this file. Values here take precedence over
# shell environment variables. Leave a key empty/commented to disable that provider.
# Keys are never written to the database, logs, evidence, or reports.

# ── NVIDIA NIM ── Parakeet STT, Nemotron live LLM, Magpie/Chatterbox TTS, judge
# Get a key: https://build.nvidia.com -> API Keys
NVIDIA_API_KEY=

# Function-ID overrides (only if NVIDIA rotates the default IDs):
# NVIDIA_PARAKEET_ASR_FUNCTION_ID=
# NVIDIA_NEMOTRON_ASR_FUNCTION_ID=
# NVIDIA_MAGPIE_TTS_FUNCTION_ID=
# NVIDIA_CHATTERBOX_TTS_FUNCTION_ID=

# gRPC/REST endpoint overrides (only for self-hosted NIM deployments):
# NVIDIA_NIM_ASR_GRPC_SERVER=grpc.nvcf.nvidia.com:443
# NVIDIA_CHATTERBOX_GRPC_SERVER=grpc.nvcf.nvidia.com:443
# NVIDIA_NIM_BASE_URL=https://integrate.api.nvidia.com/v1

# ── Gemini ── live LLM, translation fallback, LLM-as-judge
# Get a key: https://aistudio.google.com/app/apikey
GEMINI_API_KEY=

# ── Sarvam ── Indic cloud STT/TTS lane
SARVAM_API_KEY=

# ── Gnani Vachana ── cloud STT (English/Hindi + Other Indic); cloud TTS
# voices (English/Hindi only)
GNANI_API_KEY=

# ── NVIDIA/Sarvam/Gnani STT readiness probe ────────────────────────────────
# A short 16 kHz mono PCM WAV used to verify cloud STT before Setup Check
# reports it ready. The installer ships this fixture at
# ~/.veriturn/app/data/probes/nvidia_stt_probe_en.wav by default; only set
# this if you need a custom probe file.
# VERITURN_NVIDIA_STT_PROBE_WAV=/path/to/probe.wav
# VERITURN_SARVAM_STT_PROBE_WAV=/path/to/probe.wav
# VERITURN_GNANI_STT_PROBE_WAV=/path/to/probe.wav

# ── Custom sidecar paths (only if a runtime binary is installed elsewhere) ──
# VERITURN_NEMOTRON_STT_CMD=/path/to/veriturn-nemotron-stt
# VERITURN_SHERPA_STT_CMD=/path/to/sherpa-onnx-offline
# VERITURN_SHERPA_TTS_CMD=/path/to/sherpa-onnx-offline-tts

# ── Agentic VOIP (test-only; never stored in Settings/evidence) ─────────────
# Required only for Agentic AI mode. The runner and tunnel are configured in
# Settings > Agentic VOIP; credentials are env-only. See:
#   scripts/check_agentic_voip.sh   (non-dialing readiness diagnostic)
# TWILIO_ACCOUNT_SID=AC...
# TWILIO_AUTH_TOKEN=...
# TWILIO_FROM_NUMBER=+15551234567
# PLIVO_AUTH_ID=...
# PLIVO_AUTH_TOKEN=...
# PLIVO_FROM_NUMBER=+15551234567
# VERITURN_CPAAS_LIVE=0
# Public tunnel URL:
# - Default Quick mode (zero cost): leave unset; Start free Quick Tunnel in Setup Checks after app launch.
# - Optional named mode only (domain on Cloudflare):
#     cloudflared tunnel login && create veriturn-voice && route dns …
#     VERITURN_PUBLIC_BASE_URL=https://agentic-voice.YOUR_DOMAIN
ENV
  chmod 600 "$ROOT/.env"
  echo "Created $ROOT/.env (permissions: 600). Edit it to add API keys: nano $ROOT/.env"
else
  echo "$ROOT/.env already exists — not overwriting."
fi

if [[ -f "$ROOT/app/APP_VERSION" ]]; then
  installed_version="$(tr -d '[:space:]' < "$ROOT/app/APP_VERSION")"
  if [[ "$installed_version" == "$VERSION" ]]; then
    TARGET_MANIFEST="$RELEASE_ROOT/RELEASE_MANIFEST.json"
    if [[ -f "$TARGET_MANIFEST" ]] && installed_assets_current "$TARGET_MANIFEST"; then
      echo "Release $VERSION app/runtime assets are already current; running verification and model checks."
      ASSET_DIR="$RELEASE_ROOT"
      APP_ASSET_NAME="$(read_json_field_from_file "$TARGET_MANIFEST" "app.asset")"
      if [[ -n "$APP_ASSET_NAME" ]]; then
        if [[ -f "$ROOT/downloads/$VERSION/$APP_ASSET_NAME" ]]; then
          ASSET_DIR="$ROOT/downloads/$VERSION"
        fi
      fi
      "$SCRIPT_DIR/verify_release_assets.sh" "$TARGET_MANIFEST" "$ASSET_DIR"
      run_model_downloads
      print_final_summary "Installed release verification summary"
      exit 0
    fi
    echo "Release $VERSION is installed but app/runtime assets are missing, stale, or built for a different runtime variant; reinstalling exact release assets."
  elif [[ "$(printf '%s\n%s\n' "$VERSION" "$installed_version" | sort -V | tail -n 1)" == "$installed_version" ]]; then
    echo "Refusing downgrade from $installed_version to $VERSION. Restore a DB backup manually before downgrading." >&2
    exit 1
  fi
fi

RELEASE_DOWNLOAD_DIR="$DOWNLOADS/$VERSION"
mkdir -p "$RELEASE_DOWNLOAD_DIR"

MANIFEST=""
# Check downloads directory first
MANIFEST_IN_DOWNLOADS="$(find "$RELEASE_DOWNLOAD_DIR" -maxdepth 1 -type f -name 'veriturn-release-manifest-*.json' | head -n 1 || true)"
if [[ -n "$MANIFEST_IN_DOWNLOADS" ]]; then
  MANIFEST_VER="$(read_json_field_from_file "$MANIFEST_IN_DOWNLOADS" "release_version")"
  if [[ "$MANIFEST_VER" == "$VERSION" ]]; then
    MANIFEST="$MANIFEST_IN_DOWNLOADS"
  fi
fi

if [[ -z "$MANIFEST" ]]; then
  if [[ -f "$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json" ]]; then
    MANIFEST_VER="$(read_json_field_from_file "$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json" "release_version")"
    if [[ "$MANIFEST_VER" == "$VERSION" ]]; then
      MANIFEST="$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json"
    else
      # Remove stale/incorrect manifest from a previous run
      rm -f "$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json"
    fi
  fi
fi


# Check release root next
if [[ -z "$MANIFEST" ]]; then
  MANIFEST_IN_ROOT="$(find "$RELEASE_ROOT" -maxdepth 1 -type f -name 'veriturn-release-manifest-*.json' | head -n 1 || true)"
  if [[ -n "$MANIFEST_IN_ROOT" ]]; then
    MANIFEST_VER="$(read_json_field_from_file "$MANIFEST_IN_ROOT" "release_version")"
    if [[ "$MANIFEST_VER" == "$VERSION" ]]; then
      if [[ "$(realpath -m "$MANIFEST_IN_ROOT")" != "$(realpath -m "$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json")" ]]; then
        cp "$MANIFEST_IN_ROOT" "$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json"
      fi
      MANIFEST="$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json"
    fi
  fi
fi

if [[ -z "$MANIFEST" ]]; then
  if [[ -f "$RELEASE_ROOT/RELEASE_MANIFEST.json" ]]; then
    MANIFEST_VER="$(read_json_field_from_file "$RELEASE_ROOT/RELEASE_MANIFEST.json" "release_version")"
    if [[ "$MANIFEST_VER" == "$VERSION" ]]; then
      if [[ "$(realpath -m "$RELEASE_ROOT/RELEASE_MANIFEST.json")" != "$(realpath -m "$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json")" ]]; then
        cp "$RELEASE_ROOT/RELEASE_MANIFEST.json" "$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json"
      fi
      MANIFEST="$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json"
    fi
  fi
fi

# Download as last resort
if [[ -z "$MANIFEST" ]]; then
  echo "Downloading manifest for $VERSION..."
  if ! gh release download "$VERSION" --repo "$REPO" --pattern "veriturn-release-manifest-*.json" --dir "$RELEASE_DOWNLOAD_DIR"; then
    echo "Failed to download release manifest from GitHub." >&2
  fi
  MANIFEST="$(find "$RELEASE_DOWNLOAD_DIR" -maxdepth 1 -type f -name 'veriturn-release-manifest-*.json' | head -n 1 || true)"
fi

if [[ -z "$MANIFEST" ]]; then
  echo "Release manifest was not found locally or downloaded for $VERSION." >&2
  exit 1
fi
if [[ "$(realpath -m "$MANIFEST")" != "$(realpath -m "$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json")" ]]; then
  cp "$MANIFEST" "$RELEASE_DOWNLOAD_DIR/RELEASE_MANIFEST.json"
fi

eval "$(
  python3 - "$MANIFEST" <<'PY'
import json
import pathlib
import shlex
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
fields = {
    "APP_ASSET": ("app", "asset"),
    "APP_SHA": ("app", "sha256"),
}
for var, path in fields.items():
    value = manifest.get(path[0], {}).get(path[1], "")
    print(f"{var}={shlex.quote(value or '')}")

runtime_tools = manifest.get("runtime_tools", {})
cpu = runtime_tools.get("cpu", {}) if isinstance(runtime_tools.get("cpu"), dict) else {}
cuda = runtime_tools.get("cuda", {}) if isinstance(runtime_tools.get("cuda"), dict) else {}
print(f"RUNTIME_CPU_ASSET={shlex.quote(cpu.get('asset') or '')}")
print(f"RUNTIME_CPU_SHA={shlex.quote(cpu.get('sha256') or '')}")
print(f"RUNTIME_CUDA_ASSET={shlex.quote(cuda.get('asset') or '')}")
print(f"RUNTIME_CUDA_SHA={shlex.quote(cuda.get('sha256') or '')}")
PY
)"

if [[ "$GPU_MODE" == "cuda" && -z "$RUNTIME_CUDA_ASSET" ]]; then
  echo "Warning: CUDA overlay requested/detected, but this release manifest has no CUDA asset. Continuing with CPU-only runtime."
  GPU_MODE="cpu"
fi

download_asset() {
  local asset="$1"
  local expected="${2:-}"
  if [[ -z "$asset" ]]; then
    return 0
  fi

  local path="$RELEASE_DOWNLOAD_DIR/$asset"
  if [[ -f "$path" ]]; then
    if [[ -z "$expected" || "$expected" == TO_BE_FILLED_* ]]; then
      echo "Asset present in downloads (hash not checkable): $asset"
      return 0
    fi
    local actual
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [[ "$actual" == "$expected" ]]; then
      echo "Asset already present and verified: $asset"
      return 0
    else
      echo "Asset $asset is present but has incorrect hash. Redownloading..."
      rm -f "$path"
    fi
  fi

  if [[ -f "$RELEASE_ROOT/$asset" ]]; then
    if [[ "$(realpath -m "$RELEASE_ROOT/$asset")" != "$(realpath -m "$RELEASE_DOWNLOAD_DIR/$asset")" ]]; then
      # Verify release root asset first before copying
      local actual_root=""
      if [[ -n "$expected" && "$expected" != TO_BE_FILLED_* ]]; then
        actual_root="$(sha256sum "$RELEASE_ROOT/$asset" | awk '{print $1}')"
      fi
      if [[ -z "$expected" || "$expected" == TO_BE_FILLED_* || "$actual_root" == "$expected" ]]; then
        echo "Found local asset in release root: $asset. Copying to downloads..."
        cp "$RELEASE_ROOT/$asset" "$RELEASE_DOWNLOAD_DIR/$asset"
        return 0
      else
        echo "Local asset in release root $asset has incorrect hash; will download from GitHub."
      fi
    else
      # They are the same file, check hash
      local actual_same=""
      if [[ -n "$expected" && "$expected" != TO_BE_FILLED_* ]]; then
        actual_same="$(sha256sum "$path" | awk '{print $1}')"
      fi
      if [[ -z "$expected" || "$expected" == TO_BE_FILLED_* || "$actual_same" == "$expected" ]]; then
        echo "Found local asset already in downloads: $asset."
        return 0
      fi
    fi
  fi

  echo "Downloading $asset from GitHub..."
  gh release download "$VERSION" --repo "$REPO" --pattern "$asset" --dir "$RELEASE_DOWNLOAD_DIR"
}

verify_asset_hash() {
  local asset="$1"
  local expected="$2"
  if [[ -z "$asset" ]]; then
    return 0
  fi
  local path="$RELEASE_DOWNLOAD_DIR/$asset"
  if [[ ! -f "$path" ]]; then
    echo "Required release asset missing after download: $asset" >&2
    exit 1
  fi
  if [[ -z "$expected" || "$expected" == TO_BE_FILLED_* ]]; then
    echo "Warning: $asset hash is not finalized in manifest; skipping hash check."
    return 0
  fi
  local actual
  actual="$(sha256sum "$path" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "SHA-256 mismatch for $asset" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

download_asset "$APP_ASSET" "$APP_SHA"
download_asset "$RUNTIME_CPU_ASSET" "$RUNTIME_CPU_SHA"
verify_asset_hash "$APP_ASSET" "$APP_SHA"
verify_asset_hash "$RUNTIME_CPU_ASSET" "$RUNTIME_CPU_SHA"
if [[ "$GPU_MODE" == "cuda" ]]; then
  download_asset "$RUNTIME_CUDA_ASSET" "$RUNTIME_CUDA_SHA"
  verify_asset_hash "$RUNTIME_CUDA_ASSET" "$RUNTIME_CUDA_SHA"
fi

INSTALL_STAGE="$STAGING/$VERSION"
rm -rf "$INSTALL_STAGE"
mkdir -p "$INSTALL_STAGE"
tar -C "$INSTALL_STAGE" -xzf "$RELEASE_DOWNLOAD_DIR/$APP_ASSET"
if [[ -n "$RUNTIME_CPU_ASSET" && -f "$RELEASE_DOWNLOAD_DIR/$RUNTIME_CPU_ASSET" ]]; then
  tar -C "$INSTALL_STAGE" -xzf "$RELEASE_DOWNLOAD_DIR/$RUNTIME_CPU_ASSET"
fi
if [[ "$GPU_MODE" == "cuda" && -n "$RUNTIME_CUDA_ASSET" && -f "$RELEASE_DOWNLOAD_DIR/$RUNTIME_CUDA_ASSET" ]]; then
  # Overlay: extracts into the same runtime/lib tree already unpacked from the cpu bundle.
  tar -C "$INSTALL_STAGE" -xzf "$RELEASE_DOWNLOAD_DIR/$RUNTIME_CUDA_ASSET"
fi

if [[ ! -x "$INSTALL_STAGE/app/bin/veriturn-studio" ]]; then
  echo "Staged app binary is missing or not executable." >&2
  exit 1
fi
ldd "$INSTALL_STAGE/app/bin/veriturn-studio" >/dev/null
if [[ -d "$INSTALL_STAGE/runtime/bin" ]]; then
  find "$INSTALL_STAGE/runtime/bin" -maxdepth 1 -type f -perm -111 -print0 | while IFS= read -r -d '' exe; do
    LD_LIBRARY_PATH="$INSTALL_STAGE/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$exe" >/dev/null 2>&1 || true
  done
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
if [[ -d "$ROOT/db" ]]; then
  mkdir -p "$ROOT/backups/db-$timestamp"
  cp -a "$ROOT/db/." "$ROOT/backups/db-$timestamp/" 2>/dev/null || true
fi

rm -rf "$ROOT/app.new" "$ROOT/runtime.new"
cp -a "$INSTALL_STAGE/app" "$ROOT/app.new"
if [[ -d "$INSTALL_STAGE/runtime" ]]; then
  cp -a "$INSTALL_STAGE/runtime" "$ROOT/runtime.new"
else
  mkdir -p "$ROOT/runtime.new/bin" "$ROOT/runtime.new/lib"
fi

rm -rf "$ROOT/app.prev" "$ROOT/runtime.prev"
if [[ -d "$ROOT/app" ]]; then mv "$ROOT/app" "$ROOT/app.prev"; fi
if [[ -d "$ROOT/runtime" ]]; then mv "$ROOT/runtime" "$ROOT/runtime.prev"; fi
mv "$ROOT/app.new" "$ROOT/app"
mv "$ROOT/runtime.new" "$ROOT/runtime"

if [[ "$(realpath -m "$MANIFEST")" != "$(realpath -m "$ROOT/app/RELEASE_MANIFEST.json")" ]]; then
  cp "$MANIFEST" "$ROOT/app/RELEASE_MANIFEST.json"
fi
printf '%s\n' "$VERSION" > "$ROOT/app/APP_VERSION"
printf '%s\n' "$GPU_MODE" > "$ROOT/app/RUNTIME_VARIANT"
write_installed_asset_state "$MANIFEST"

"$SCRIPT_DIR/verify_release_assets.sh" "$ROOT/app/RELEASE_MANIFEST.json" "$RELEASE_DOWNLOAD_DIR"

# ──────────────────────────────────────────────────────────────────────────────
#  Bluetooth HFP setup for live call audio
# ──────────────────────────────────────────────────────────────────────────────
echo
echo "== Bluetooth HFP setup for live call audio =="
echo "VeriTurn captures call audio from your Android phone via Bluetooth HFP"
echo "(Hands-Free Profile). This verifies the service, guides pairing, and writes"
echo "the PipeWire HFP role config so the PC acts as a Hands-Free device."
echo

if systemctl is-active bluetooth >/dev/null 2>&1; then
  echo "Bluetooth service is active."
else
  echo "Bluetooth service is NOT active. Enable it with:"
  echo "    sudo systemctl start bluetooth && sudo systemctl enable bluetooth"
fi

if command -v bluetoothctl >/dev/null 2>&1; then
  paired="$(bluetoothctl devices Paired 2>/dev/null | wc -l || echo 0)"
  if [[ "$paired" -gt 0 ]]; then
    echo "Found $paired paired Bluetooth device(s)."
  else
    echo "No paired Bluetooth devices found. To pair your Android test phone:"
    echo "    bluetoothctl"
    echo "      > power on; agent on; scan on; pair <PHONE_MAC>; trust <PHONE_MAC>; connect <PHONE_MAC>"
    echo "  Then enable 'Calls' / 'Phone audio' (not just media) for this PC on the phone."
  fi
else
  echo "Warning: bluetoothctl not found — install bluez: sudo apt install bluez"
fi

WP_VERSION="$(wireplumber --version 2>/dev/null | grep "Linked with libwireplumber" | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "0.4.0")"
WP_MAJOR="$(printf '%s' "$WP_VERSION" | cut -d. -f1)"
WP_MINOR="$(printf '%s' "$WP_VERSION" | cut -d. -f2)"
use_wp_conf=false
if [[ "$WP_MAJOR" -gt 0 ]] || { [[ "$WP_MAJOR" -eq 0 ]] && [[ "$WP_MINOR" -ge 5 ]]; }; then
  use_wp_conf=true
fi

if $use_wp_conf; then
  WP_CONF_DIR="$HOME/.config/wireplumber/wireplumber.conf.d"
  WP_CONF_FILE="$WP_CONF_DIR/10-bluetooth-hfp.conf"
  if find "$WP_CONF_DIR" -maxdepth 1 -name "*.conf" 2>/dev/null | grep -q .; then
    echo "WirePlumber Bluetooth config already exists under $WP_CONF_DIR."
  else
    mkdir -p "$WP_CONF_DIR"
    cat > "$WP_CONF_FILE" <<'WP_CONF_CONTENT'
# VeriTurn Studio — WirePlumber Bluetooth HFP Hands-Free configuration.
monitor.bluez.properties = {
    bluez5.roles = [ a2dp_sink a2dp_source hsp_hs hsp_ag hfp_hf hfp_ag ]
    bluez5.enable-msbc = true
    bluez5.enable-sbc-xq = true
    bluez5.hfphsp-backend = "native"
}
WP_CONF_CONTENT
    echo "Created $WP_CONF_FILE. Restart services to activate:"
    echo "    systemctl --user restart wireplumber pipewire pipewire-pulse && sudo systemctl restart bluetooth"
  fi
else
  WP_LUA_DIR="$HOME/.config/wireplumber/bluetooth.lua.d"
  WP_LUA_FILE="$WP_LUA_DIR/50-bluetooth-hfp.lua"
  if find "$WP_LUA_DIR" -maxdepth 1 -name "*.lua" 2>/dev/null | grep -q .; then
    echo "WirePlumber 0.4.x Bluetooth Lua config already exists under $WP_LUA_DIR."
  else
    mkdir -p "$WP_LUA_DIR"
    cat > "$WP_LUA_FILE" <<'WP_LUA_CONTENT'
-- VeriTurn Studio — WirePlumber 0.4.x Bluetooth HFP Hands-Free configuration.
bluez_monitor.properties = {
    ["bluez5.roles"]            = { "a2dp_sink", "a2dp_source", "hsp_hs", "hsp_ag", "hfp_hf", "hfp_ag" },
    ["bluez5.enable-msbc"]      = true,
    ["bluez5.enable-sbc-xq"]    = true,
    ["bluez5.hfphsp-backend"]   = "native",
}
WP_LUA_CONTENT
    echo "Created $WP_LUA_FILE. Restart services to activate:"
    echo "    systemctl --user restart wireplumber pipewire pipewire-pulse && sudo systemctl restart bluetooth"
  fi
fi
echo "Note: Bluetooth HFP call-audio nodes only appear in PipeWire DURING an active"
echo "cellular call with phone audio explicitly routed to this PC. Verify with:"
echo "    $RELEASE_ROOT/scripts/check_ubuntu_audio.sh"

# ──────────────────────────────────────────────────────────────────────────────
#  ADB and USB debugging
# ──────────────────────────────────────────────────────────────────────────────
echo
echo "== ADB and Android phone USB debugging =="
if command -v adb >/dev/null 2>&1; then
  echo "ADB found: $(command -v adb)"
  adb_devices="$(adb devices 2>/dev/null | grep -v "List of devices" | grep -c "device$" || true)"
  if [[ "$adb_devices" -ge 1 ]]; then
    echo "$adb_devices authorized Android device(s) detected via ADB."
  else
    echo "No authorized ADB device detected right now. On the test phone:"
    echo "    Settings -> About Phone -> tap Build Number 7 times -> Developer Options -> USB Debugging: ON"
    echo "  Connect via USB and tap Allow, then verify: adb devices"
  fi
else
  echo "ADB not found. Install it: sudo apt install -y adb"
fi

# ──────────────────────────────────────────────────────────────────────────────
#  Local model downloads and final status
# ──────────────────────────────────────────────────────────────────────────────
run_model_downloads

print_final_summary "Final status summary"

echo
echo "Install complete."
