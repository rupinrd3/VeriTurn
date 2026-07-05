# Release Notes

## Current Private Release

- Runtime tools (llama-server, whisper-server, piper, piper-tts-server,
  sherpa-onnx STT/TTS, veriturn-nemotron-stt) are pre-packaged binaries; no
  build tooling is required on the install machine.
- Runtime tools ship as two GitHub Release assets: a CPU-only bundle
  (~30–65 MB) and an optional CUDA overlay (~450 MB) for GPU-accelerated
  local inference. The installer auto-detects an NVIDIA GPU via `nvidia-smi`
  and downloads only what's needed; override with `--force-cpu`/`--force-cuda`.
- The installer downloads default open-license STT/TTS models automatically
  (Whisper `small.en`, four Piper English/Hindi voices, ~350 MB total) so
  Setup Check passes on first launch without a manual model hunt. Larger or
  gated models (Nemotron ONNX, sherpa Indic STT/TTS, translation, a local
  LLM GGUF) remain user-installed, or a cloud provider can be selected
  instead.
- Approved online providers — Gemini (live LLM, translation fallback,
  advisory judge), NVIDIA NIM (Parakeet STT, Nemotron live LLM,
  Magpie/Chatterbox TTS, advisory judge), and Sarvam (Indic cloud STT/TTS)
  — are disabled by default, tester-selected, and read API keys only from
  `~/.veriturn/.env`.
- User data, evidence, logs, recordings, settings, and model files remain
  local user-owned files under `~/.veriturn`; nothing is uploaded except
  what an explicitly selected cloud provider needs to service that
  provider's request.
- Ubuntu 22.04+ (x86_64) is the first certified installation target.
  Windows is not supported by this release.
- Every release asset (app tarball, CPU/CUDA runtime tarballs) is verified
  by SHA-256 against `RELEASE_MANIFEST.json` before and after install.

For upgrade-time behavior and rollback limits, see `docs/upgrade.md`. For
the full historical changelog once subsequent versions ship, see
`docs/release_notes_archive.md`.
