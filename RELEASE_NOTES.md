# Release Notes

## Current Private Release

- Version 3.0.0 brings Agentic Mission Control call sessions up to full engine parity with Human mode: every LLM, STT, and TTS engine available to a human-supervised session is now selectable, armed, and executed in Agentic mode with the same provider behavior, readiness semantics, model provenance, and language gates.

- Agentic STT and TTS now route through the same Rust provider adapters Human mode uses (`rust_stt_adapter` / `rust_tts_adapter`) instead of a Whisper-only transcription path and a local-Piper-only synthesis path. The Python media runner remains a pure CPaaS media transport and VAD/playout mechanism — it does not implement or select provider behavior.

- Agentic readiness now blocks on real missing prerequisites per engine (no reporting Human-mode support as Agentic support), and STT/TTS runtime events carry selected engine, provider, model, voice/language, and confidence metadata for evidence and reporting.

- As with every other cloud provider, no API key is ever persisted, logged, or exposed in runner output, evidence exports, or report content, and a runtime failure never silently switches providers or engines.

- No database migration; no change to Human-mode behavior; no new dependency.

For upgrade-time behavior and rollback limits, see `docs/upgrade.md`. For
the full historical changelog once subsequent versions ship, see
`docs/release_notes_archive.md`.
