# Cloud Provider Keys

VeriTurn's default operating mode is local, offline model inference. Cloud
providers are explicit, tester-selected alternatives — never a hidden
fallback — and are disabled until you both add a key here and select the
provider in Settings.

## Where keys live

Keys are read only from the environment or from `~/.veriturn/.env` (created
by the installer with mode `600`, owner read/write only):

```bash
GEMINI_API_KEY=
NVIDIA_API_KEY=
SARVAM_API_KEY=
GNANI_API_KEY=
```

Edit with:

```bash
nano ~/.veriturn/.env
```

Keys are **never** written to the database, logs, evidence exports, reports,
or Git remotes. If you ever see a key value anywhere other than this file,
treat that as a bug and stop using the affected evidence/export until it is
fixed.

## Providers and what they unlock

| Provider | Env var | Unlocks |
|---|---|---|
| Gemini | `GEMINI_API_KEY` | Live LLM response-option generation, offline translation fallback, LLM-as-a-Judge (advisory) |
| NVIDIA NIM | `NVIDIA_API_KEY` | Parakeet cloud STT, Nemotron live LLM, Magpie/Chatterbox cloud TTS voices, advisory judge |
| Sarvam | `SARVAM_API_KEY` | Sarvam cloud STT/TTS lane for Indic languages |
| Gnani Vachana | `GNANI_API_KEY` | Gnani cloud STT (English/Hindi and Other Indic); Gnani cloud TTS voices (English/Hindi only) |

Get a key:

- Gemini: <https://aistudio.google.com/app/apikey>
- NVIDIA NIM: <https://build.nvidia.com> → API Keys

## Optional overrides

These are only needed if you use a non-default function ID, a self-hosted
NIM endpoint, or a custom probe/binary path. Leave them commented out
otherwise — the installer's `.env` template includes commented examples for
all of them:

```bash
# NVIDIA function-ID overrides (only if NVIDIA rotates the default IDs)
NVIDIA_PARAKEET_ASR_FUNCTION_ID=
NVIDIA_NEMOTRON_ASR_FUNCTION_ID=
NVIDIA_MAGPIE_TTS_FUNCTION_ID=
NVIDIA_CHATTERBOX_TTS_FUNCTION_ID=

# Self-hosted NIM endpoint overrides
NVIDIA_NIM_ASR_GRPC_SERVER=
NVIDIA_CHATTERBOX_GRPC_SERVER=
NVIDIA_NIM_BASE_URL=

# Cloud STT readiness probe overrides (a short 16 kHz mono WAV; the shipped
# fixture at ~/.veriturn/app/data/probes/nvidia_stt_probe_en.wav is used by
# default and covers NVIDIA, Sarvam, and Gnani STT readiness checks)
VERITURN_NVIDIA_STT_PROBE_WAV=
VERITURN_SARVAM_STT_PROBE_WAV=
VERITURN_GNANI_STT_PROBE_WAV=

# Custom sidecar binary paths (only if a runtime binary is installed
# somewhere other than ~/.veriturn/runtime)
VERITURN_NEMOTRON_STT_CMD=
VERITURN_SHERPA_STT_CMD=
VERITURN_SHERPA_TTS_CMD=
```

## Readiness

Setup Check / Global Health Check report each selected cloud provider as
ready, degraded, or blocked — the same authoritative readiness gate used
before a live call starts. A missing or invalid key blocks that provider's
lane; it never silently substitutes a different provider or a local model.

## Data disclosure

Selecting a cloud provider sends the relevant turn/session data (audio for
STT/TTS, transcript/context for LLM/judge/translation) to that provider's
API. Confirm this is acceptable for your engagement's data-handling
requirements before enabling a cloud provider, and do not enter real
customer PII into any session (see `LICENSE.txt`).
