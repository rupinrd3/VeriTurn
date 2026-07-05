# Hardware Readiness

VeriTurn Studio needs a real Android test phone reachable over Bluetooth HFP
(or a validated audio bridge), USB ADB for dialer control, and a working
PipeWire/WirePlumber audio stack. Live-call start gates on a single
authoritative readiness check covering ADB + provider + audio route +
sidecars + models + storage + recording authorization — Settings → **Setup
Check** and **Global Health Check** run this same check.

## Quick diagnostic

```bash
scripts/check_ubuntu_audio.sh
```

Non-destructive: reports OS/kernel, presence of `adb`/`bluetoothctl`/`pactl`/
`pw-cli`/`pw-record`/`pw-play`, PipeWire/PulseAudio sources and sinks,
Bluetooth pairing state, ADB device list, and which `~/.veriturn` release
paths exist. Run it any time you suspect an audio or phone-control issue.

## Bluetooth HFP (call audio)

`scripts/setup_ubuntu.sh` guides this during install/upgrade; you can also
re-run it standalone via `bluetoothctl`:

```bash
sudo systemctl start bluetooth && sudo systemctl enable bluetooth
bluetoothctl
  > power on
  > agent on
  > scan on
  > pair <PHONE_MAC>
  > trust <PHONE_MAC>
  > connect <PHONE_MAC>
```

On the phone, enable **Calls / Phone audio** (not just media audio) for this
PC. The installer writes a WirePlumber Hands-Free role config so the PC
advertises HFP roles correctly:

- WirePlumber 0.5+: `~/.config/wireplumber/wireplumber.conf.d/10-bluetooth-hfp.conf`
- WirePlumber 0.4.x: `~/.config/wireplumber/bluetooth.lua.d/50-bluetooth-hfp.lua`

After the config is created, restart the audio stack:

```bash
systemctl --user restart wireplumber pipewire pipewire-pulse
sudo systemctl restart bluetooth
```

**Important:** Bluetooth HFP call-audio nodes only appear in PipeWire
*during an active cellular call* with phone audio explicitly routed to this
PC — they will not show up just from pairing. Start a test call and route
audio to the PC, then check with `check_ubuntu_audio.sh` or Setup Check.

## ADB / USB debugging

```bash
sudo apt install -y adb
```

On the Android test phone: **Settings → About Phone → tap Build Number 7
times → Developer Options → USB Debugging: ON**. Connect via USB, tap
**Allow** on the phone's authorization prompt, then confirm:

```bash
adb devices
```

An unauthorized or missing device blocks live-call readiness until fixed.

## GPU acceleration (optional)

The installer detects an NVIDIA GPU via `nvidia-smi -L` and downloads a CUDA
runtime overlay automatically when one is found; CPU-only machines get the
smaller CPU-only bundle. Override with `--force-cpu` (skip CUDA even if a
GPU is present) or `--force-cuda` (install CUDA libraries even without a
detected GPU — the app falls back to CPU at runtime if the driver is
unusable). The installed variant is recorded in
`~/.veriturn/app/RUNTIME_VARIANT` and shown in the installer's final status
summary and in `scripts/verify_release_assets.sh` output. GPU acceleration
affects local llama.cpp/whisper.cpp/onnxruntime inference speed only — it
has no effect on cloud provider lanes (Gemini/NVIDIA NIM/Sarvam).

## Fonts

Bengali, Devanagari, Telugu, and other Indic scripts need Noto fonts to
render correctly in the live call transcript, or they show as boxes:

```bash
sudo apt install -y fonts-noto fonts-noto-core fonts-noto-ui-core fonts-noto-extra
```

## Local models (auto-downloaded or guided)

`scripts/setup_ubuntu.sh` downloads these automatically (skip with
`--skip-models`, or run later with `scripts/download_default_models.sh`):

- `models/stt/ggml-small.en.bin` — Whisper small.en (STT fallback, ~150 MB)
- `models/stt/ggml-indic-whisper-medium-f16.bin` — IndicWhisper fallback for other Indic STT
- `models/stt/nemotron-3.5-asr-streaming-0.6b-onnx/` — Nemotron ONNX, high-fidelity English/Hindi STT
- `models/stt/sherpa-onnx-whisper-large-v3/` — sherpa, other Indic-language STT
- `models/tts/en_US-lessac-high.onnx(.json)` — Piper English voice
- `models/tts/en_US-ryan-high.onnx(.json)` — Piper English voice
- `models/tts/hi_IN-priyamvada-medium.onnx(.json)` — Piper Hindi voice
- `models/tts/hi_IN-rohan-medium.onnx(.json)` — Piper Hindi voice
- `models/tts/sherpa-vits-mms/` — sherpa Indic TTS voices (Bengali/Marathi/Telugu/Tamil/Gujarati/Kannada)
- `models/tts/kokoro-82m-v1.0.onnx` plus tokens/voices/espeak assets — optional higher-quality English voice
- `models/llm/*.gguf` — default local GGUF where Hugging Face access allows it
- `models/translation/indictrans2-indic-en-*` — CT2/IndicTrans2 when `hf` is authenticated and gated terms are accepted

Large or gated downloads remain explicit: the setup helper prompts for
Hugging Face CLI login and terms acceptance where required. If a model host
or gated access is unavailable, the final installer summary marks the exact
missing component and the app blocks only that selected lane. Cloud providers
remain explicit alternatives in Settings.

The sherpa/Nemotron/Piper/whisper-server/llama-server *binaries* themselves
are already bundled in the runtime tarball and need no separate install —
only their model files are user-supplied.

## Cloud providers as an alternative to local models

Every local-model dependency above (STT, LLM, TTS, translation, judge) has
an explicit, tester-selected cloud alternative (Gemini, NVIDIA NIM, Sarvam)
that needs only an API key in `~/.veriturn/.env` and no model download — see
`cloud_provider_keys.md`. Cloud providers are never a hidden fallback: they
only run when you explicitly select them in Settings.
