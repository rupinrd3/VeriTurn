#!/usr/bin/env bash
# VeriTurn Studio — local model download helper for the release installer.
# Re-runnable and resumable. It installs the full default local model set that
# can be downloaded without an interactive build from source. Gated/provider
# models are attempted only when credentials are already available, then reported
# clearly so the app blocks visibly instead of silently falling back.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Auto-detect custom VERITURN_HOME if a .shim file or directory exists in the release root
if [[ -z "${VERITURN_HOME:-}" && -e "$RELEASE_ROOT/.shim" ]]; then
  export VERITURN_HOME="$RELEASE_ROOT"
fi

ROOT="${VERITURN_HOME:-$HOME/.veriturn}"
STT_DIR="$ROOT/models/stt"
TTS_DIR="$ROOT/models/tts"
LLM_DIR="$ROOT/models/llm"
TRANSLATION_DIR="$ROOT/models/translation"
TMP_DIR="$ROOT/downloads/model-tmp"
FORCE=0
MINIMAL=0
NON_INTERACTIVE=0
FAILED=0

usage() {
  cat <<'USAGE'
Usage: scripts/download_default_models.sh [--force] [--minimal] [--non-interactive]

Downloads the local runtime models used by VeriTurn's default/recommended paths:
  - Whisper small.en GGML fallback
  - IndicWhisper GGUF fallback for other Indic languages
  - Nemotron/Parakeet ONNX English/Hindi STT artifacts
  - sherpa Whisper large-v3 other-Indic STT artifacts
  - Piper English/Hindi voices
  - sherpa MMS Bengali/Marathi/Telugu/Tamil/Gujarati/Kannada voices
  - Kokoro English voice assets
  - Default local GGUF LLM when publicly reachable or HF credentials are present
  - CT2/IndicTrans2 offline translation artifacts when hf is authenticated

--minimal downloads only Whisper small.en plus Piper English/Hindi voices.
--non-interactive never prompts for Hugging Face login or terms acceptance.

Already-present files are skipped unless --force is passed.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --minimal)
      MINIMAL=1
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
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

mkdir -p "$STT_DIR" "$TTS_DIR" "$LLM_DIR" "$TRANSLATION_DIR" "$TMP_DIR"

auth_args=()
if [[ -n "${HF_TOKEN:-}" ]]; then
  auth_args=(--header "Authorization: Bearer ${HF_TOKEN}")
elif [[ -n "${HUGGINGFACE_TOKEN:-}" ]]; then
  auth_args=(--header "Authorization: Bearer ${HUGGINGFACE_TOKEN}")
fi

has_tty() {
  [[ "$NON_INTERACTIVE" -ne 1 ]] && [[ -r /dev/tty ]]
}

prompt_yes() {
  local prompt="$1"
  local ans=""
  has_tty || return 1
  read -r -p "$prompt" ans </dev/tty
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

open_in_browser() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import webbrowser; webbrowser.open('$url')" >/dev/null 2>&1 || true
  fi
}

hf_ready() {
  command -v hf >/dev/null 2>&1 && hf auth whoami >/dev/null 2>&1
}

ensure_hf_ready() {
  if hf_ready; then
    return 0
  fi
  if ! command -v hf >/dev/null 2>&1; then
    echo "  [WARN]  hf CLI is not installed."
    echo "          Install command: python3 -m pip install -U 'huggingface_hub[cli]' --user"
    if prompt_yes "  Install hf CLI now with python3 -m pip --user? (y/N): "; then
      if python3 -m pip install -U 'huggingface_hub[cli]' --user; then
        export PATH="$HOME/.local/bin:$PATH"
        hash -r 2>/dev/null || true
      fi
    fi
  fi
  if command -v hf >/dev/null 2>&1 && ! hf auth whoami >/dev/null 2>&1; then
    echo "  [WARN]  hf CLI is not authenticated."
    echo "          Create a read token at https://huggingface.co/settings/tokens"
    if prompt_yes "  Launch hf login now? (y/N): "; then
      hf login || true
    fi
  fi
  hf_ready
}

ensure_hf_terms_accepted() {
  local repo_id="$1"
  local page_url="$2"
  local label="$3"
  if ! ensure_hf_ready; then
    echo "  [WARN]  Cannot download $label without authenticated hf CLI."
    return 1
  fi
  echo
  echo "  Terms of Use may be required for $label"
  echo "  HF ID: $repo_id"
  echo "  Page:  $page_url"
  if has_tty; then
    open_in_browser "$page_url"
    if ! prompt_yes "  Type y after accepting access/terms in the browser (y/N): "; then
      echo "  [WARN]  Terms not confirmed for $label."
      return 1
    fi
  else
    echo "  [WARN]  Non-interactive mode: terms must already be accepted."
  fi
  return 0
}

hf_download_file() {
  local repo="$1"
  local filename="$2"
  local dest_dir="$3"
  local repo_type="${4:-model}"
  if ! ensure_hf_ready; then
    return 1
  fi
  hf download "$repo" "$filename" --repo-type "$repo_type" --local-dir "$dest_dir"
}

download() {
  local dest="$1"
  local url="$2"
  if [[ -f "$dest" && "$FORCE" -ne 1 ]]; then
    echo "  [SKIP]  $(basename "$dest") already present"
    return 0
  fi
  echo "  Downloading $(basename "$dest")..."
  if wget "${auth_args[@]}" -q --show-progress -c -O "$dest" "$url"; then
    echo "  [OK]    $(basename "$dest")"
  else
    rm -f "$dest"
    echo "  [WARN]  Failed to download $(basename "$dest") from $url" >&2
    FAILED=1
  fi
}

download_archive() {
  local label="$1"
  local url="$2"
  local tmp="$3"
  local dest_dir="$4"
  local marker="$5"
  local strip_components="${6:-1}"

  if [[ -e "$marker" && "$FORCE" -ne 1 ]]; then
    echo "  [SKIP]  $label already present"
    return 0
  fi

  mkdir -p "$dest_dir" "$(dirname "$tmp")"
  echo "  Downloading $label..."
  if ! wget "${auth_args[@]}" -q --show-progress -c -O "$tmp" "$url"; then
    rm -f "$tmp"
    echo "  [WARN]  Failed to download $label from $url" >&2
    FAILED=1
    return 0
  fi

  echo "  Extracting $label..."
  if [[ "$tmp" == *.tar.bz2 ]]; then
    tar -xjf "$tmp" -C "$dest_dir" --strip-components="$strip_components"
  else
    tar -xzf "$tmp" -C "$dest_dir" --strip-components="$strip_components"
  fi
  echo "  [OK]    $label"
}

echo "== Whisper STT fallback model (~150 MB) =="
download "$STT_DIR/ggml-small.en.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"

echo
echo "== Piper TTS voices — English + Hindi (~200 MB) =="
PIPER_PAIRS=(
  "$TTS_DIR/en_US-lessac-high.onnx:https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/high/en_US-lessac-high.onnx"
  "$TTS_DIR/en_US-lessac-high.onnx.json:https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/high/en_US-lessac-high.onnx.json"
  "$TTS_DIR/en_US-ryan-high.onnx:https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high/en_US-ryan-high.onnx"
  "$TTS_DIR/en_US-ryan-high.onnx.json:https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high/en_US-ryan-high.onnx.json"
  "$TTS_DIR/hi_IN-priyamvada-medium.onnx:https://huggingface.co/rhasspy/piper-voices/resolve/main/hi/hi_IN/priyamvada/medium/hi_IN-priyamvada-medium.onnx"
  "$TTS_DIR/hi_IN-priyamvada-medium.onnx.json:https://huggingface.co/rhasspy/piper-voices/resolve/main/hi/hi_IN/priyamvada/medium/hi_IN-priyamvada-medium.onnx.json"
  "$TTS_DIR/hi_IN-rohan-medium.onnx:https://huggingface.co/rhasspy/piper-voices/resolve/main/hi/hi_IN/rohan/medium/hi_IN-rohan-medium.onnx"
  "$TTS_DIR/hi_IN-rohan-medium.onnx.json:https://huggingface.co/rhasspy/piper-voices/resolve/main/hi/hi_IN/rohan/medium/hi_IN-rohan-medium.onnx.json"
)
for pair in "${PIPER_PAIRS[@]}"; do
  download "${pair%%:*}" "${pair#*:}"
done

if [[ "$MINIMAL" -eq 1 ]]; then
  echo
  echo "Minimal model set installed under: $STT_DIR and $TTS_DIR"
  exit "$FAILED"
fi

echo
echo "== IndicWhisper GGUF fallback for other Indic STT (~1.5 GB) =="
download "$STT_DIR/ggml-indic-whisper-medium-f16.bin" \
  "https://huggingface.co/rupind/indic-whisper-medium-gguf/resolve/main/ggml-indic-whisper-medium-f16.bin"

echo
echo "== Nemotron/Parakeet ONNX English/Hindi STT artifacts (~2.5 GB) =="
NEMO_DIR="$STT_DIR/nemotron-3.5-asr-streaming-0.6b-onnx"
mkdir -p "$NEMO_DIR"
NEMO_BASE="https://huggingface.co/altunenes/parakeet-rs/resolve/main/nemotron-3.5-asr-streaming-0.6b-onnx"
download "$NEMO_DIR/encoder.onnx" "$NEMO_BASE/encoder.onnx"
download "$NEMO_DIR/encoder.onnx.data" "$NEMO_BASE/encoder.onnx.data"
download "$NEMO_DIR/decoder_joint.onnx" "$NEMO_BASE/decoder_joint.onnx"
download "$NEMO_DIR/tokenizer.model" "$NEMO_BASE/tokenizer.model"
if [[ -f "$NEMO_DIR/decoder_joint.onnx" && ! -f "$NEMO_DIR/decoder.onnx" ]]; then
  cp "$NEMO_DIR/decoder_joint.onnx" "$NEMO_DIR/decoder.onnx"
fi

echo
echo "== sherpa-onnx Whisper large-v3 STT for other Indic languages (~3 GB) =="
download_archive \
  "sherpa-onnx Whisper large-v3 STT" \
  "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-large-v3.tar.bz2" \
  "$TMP_DIR/sherpa-onnx-whisper-large-v3.tar.bz2" \
  "$STT_DIR/sherpa-onnx-whisper-large-v3" \
  "$STT_DIR/sherpa-onnx-whisper-large-v3/large-v3-encoder.int8.onnx" \
  1

echo
echo "== sherpa MMS TTS voices for Bengali/Marathi/Telugu/Tamil/Gujarati/Kannada (~60 MB) =="
MMS_DIR="$TTS_DIR/sherpa-vits-mms"
mkdir -p "$MMS_DIR"
for lang in ben mar tel tam guj kan; do
  if [[ -f "$MMS_DIR/vits-mms-${lang}.onnx" && "$FORCE" -ne 1 ]]; then
    echo "  [SKIP]  vits-mms-${lang}.onnx already present"
    continue
  fi
  tmp="$TMP_DIR/vits-mms-${lang}.tar.bz2"
  ex="$TMP_DIR/vits-mms-${lang}-extract"
  rm -rf "$ex"
  mkdir -p "$ex"
  echo "  Downloading vits-mms-${lang}..."
  if wget "${auth_args[@]}" -q --show-progress -c -O "$tmp" "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-mms-${lang}.tar.bz2"; then
    tar -xjf "$tmp" -C "$ex"
    onnx_path="$(find "$ex" -type f -name "model.onnx" | head -n 1 || true)"
    tokens_path="$(find "$ex" -type f -name "tokens.txt" | head -n 1 || true)"
    if [[ -n "$onnx_path" ]]; then
      cp "$onnx_path" "$MMS_DIR/vits-mms-${lang}.onnx"
    fi
    if [[ -n "$tokens_path" ]]; then
      cp "$tokens_path" "$MMS_DIR/tokens-${lang}.txt"
    fi
    echo "  [OK]    vits-mms-${lang}"
  else
    rm -f "$tmp"
    echo "  [WARN]  Failed to download vits-mms-${lang}" >&2
    FAILED=1
  fi
  rm -rf "$ex"
done

echo
echo "== Kokoro English TTS assets (~350 MB) =="
KOKORO_ROOT="$TMP_DIR/kokoro-en-extract"
if [[ -f "$TTS_DIR/kokoro-82m-v1.0.onnx" && -f "$TTS_DIR/tokens.txt" && -f "$TTS_DIR/voices.bin" && "$FORCE" -ne 1 ]]; then
  echo "  [SKIP]  Kokoro assets already present"
else
  rm -rf "$KOKORO_ROOT"
  mkdir -p "$KOKORO_ROOT"
  kokoro_tmp="$TMP_DIR/kokoro-en-v0_19.tar.bz2"
  echo "  Downloading Kokoro package..."
  if wget "${auth_args[@]}" -q --show-progress -c -O "$kokoro_tmp" "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2"; then
    tar -xjf "$kokoro_tmp" -C "$KOKORO_ROOT"
    cp "$KOKORO_ROOT/kokoro-en-v0_19/model.onnx" "$TTS_DIR/kokoro-82m-v1.0.onnx"
    cp "$KOKORO_ROOT/kokoro-en-v0_19/tokens.txt" "$TTS_DIR/tokens.txt"
    cp "$KOKORO_ROOT/kokoro-en-v0_19/voices.bin" "$TTS_DIR/voices.bin"
    rm -rf "$TTS_DIR/espeak-ng-data"
    cp -a "$KOKORO_ROOT/kokoro-en-v0_19/espeak-ng-data" "$TTS_DIR/espeak-ng-data"
    echo "  [OK]    Kokoro assets"
  else
    rm -f "$kokoro_tmp"
    echo "  [WARN]  Failed to download Kokoro assets" >&2
    FAILED=1
  fi
  rm -rf "$KOKORO_ROOT"
fi

echo
echo "== Default local LLM GGUF (~5 GB; requires public access or HF token if gated) =="
DEFAULT_LLM_REPO="google/gemma-4-E4B-it-qat-q4_0-gguf"
DEFAULT_LLM_GGUF="gemma-4-E4B_q4_0-it.gguf"
if [[ -f "$LLM_DIR/$DEFAULT_LLM_GGUF" && "$FORCE" -ne 1 ]]; then
  echo "  [SKIP]  $DEFAULT_LLM_GGUF already present"
else
  if hf_download_file "$DEFAULT_LLM_REPO" "$DEFAULT_LLM_GGUF" "$LLM_DIR" model; then
    echo "  [OK]    $DEFAULT_LLM_GGUF"
  else
    echo "  [WARN]  hf download failed for $DEFAULT_LLM_GGUF; trying direct URL."
    download "$LLM_DIR/$DEFAULT_LLM_GGUF" \
      "https://huggingface.co/$DEFAULT_LLM_REPO/resolve/main/$DEFAULT_LLM_GGUF"
  fi
fi

echo
echo "== CT2/IndicTrans2 offline translation artifacts (~6 GB; gated HF terms) =="
INDIC_BASE_DIR="$TRANSLATION_DIR/indictrans2-indic-en-1B"
CT2_DIR="$TRANSLATION_DIR/indictrans2-indic-en-ct2"
CT2_INT8_DIR="$TRANSLATION_DIR/indictrans2-indic-en-ct2-int8"
BPCC_TAR="$TRANSLATION_DIR/additional/indic-en-preprint.tar.gz"
mkdir -p "$INDIC_BASE_DIR" "$CT2_DIR" "$CT2_INT8_DIR" "$(dirname "$BPCC_TAR")"

if [[ -f "$CT2_DIR/model.bin" && "$FORCE" -ne 1 ]]; then
  echo "  [SKIP]  CT2/IndicTrans2 artifacts already present"
elif ensure_hf_terms_accepted \
    "ai4bharat/indictrans2-indic-en-1B" \
    "https://huggingface.co/ai4bharat/indictrans2-indic-en-1B" \
    "IndicTrans2 base model" &&
    ensure_hf_terms_accepted \
      "ai4bharat/BPCC" \
      "https://huggingface.co/datasets/ai4bharat/BPCC" \
      "BPCC CT2 archive"; then
  if [[ ! -f "$INDIC_BASE_DIR/pytorch_model.bin" && ! -f "$INDIC_BASE_DIR/model.safetensors" || "$FORCE" -eq 1 ]]; then
    echo "  Downloading IndicTrans2 base model with hf..."
    if ! hf download ai4bharat/indictrans2-indic-en-1B --repo-type model --local-dir "$INDIC_BASE_DIR"; then
      echo "  [WARN]  IndicTrans2 base download failed. Accept terms at https://huggingface.co/ai4bharat/indictrans2-indic-en-1B and retry." >&2
      FAILED=1
    fi
  else
    echo "  [SKIP]  IndicTrans2 base model already present"
  fi

  if [[ ! -f "$BPCC_TAR" || "$FORCE" -eq 1 ]]; then
    echo "  Downloading BPCC CT2 archive with hf..."
    if ! hf download ai4bharat/BPCC additional/indic-en-preprint.tar.gz --repo-type dataset --local-dir "$TRANSLATION_DIR"; then
      echo "  [WARN]  BPCC CT2 archive download failed. Accept terms at https://huggingface.co/datasets/ai4bharat/BPCC and retry." >&2
      FAILED=1
    fi
  else
    echo "  [SKIP]  BPCC CT2 archive already present"
  fi

  if [[ -f "$BPCC_TAR" ]]; then
    echo "  Extracting CT2 fp16/int8 artifacts..."
    if tar -xzf "$BPCC_TAR" --strip-components=2 -C "$CT2_DIR" indic-en-preprint/ct2_fp16_model/ &&
       tar -xzf "$BPCC_TAR" --strip-components=2 -C "$CT2_INT8_DIR" indic-en-preprint/ct2_int8_model/; then
      echo "  [OK]    CT2/IndicTrans2 artifacts"
    else
      echo "  [WARN]  CT2 artifact extraction failed" >&2
      FAILED=1
    fi
  fi
else
  echo "  [WARN]  CT2/IndicTrans2 remains unavailable."
  echo "          Run: scripts/download_default_models.sh after hf login and terms acceptance."
  FAILED=1
fi

echo
echo "Model download pass complete. Root: $ROOT/models"
if [[ "$FAILED" -ne 0 ]]; then
  echo "One or more downloads failed. Re-run this script; partial files were removed."
fi
exit "$FAILED"
