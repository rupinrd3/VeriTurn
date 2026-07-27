# Release Notes Archive

`RELEASE_NOTES.md` at the repo root always describes the **current** private
release only. This file is the running history: each time a new version is
published, that version's `RELEASE_NOTES.md` content is appended below
before it is overwritten with the next release's notes, so nothing is lost.

## Format

Each entry follows this structure:

```markdown
## vX.Y.Z — YYYY-MM-DD

- Summary of what changed for release users (features, fixes, breaking
  changes to installer flags or file layout, new minimum OS/hardware
  requirements).
- Any upgrade-time caveats (forced database migration, downgrade
  restrictions introduced, changed default settings).
```

## History

## v2.3.0 — 2026-07-25

- Version 2.3.0 adds Gnani Vachana as a fourth explicit, tester-selected, disabled-by-default cloud speech provider, alongside NVIDIA NIM and Sarvam. Gnani STT is available for both language groups (English/Hindi and Other Indic); Gnani TTS voices are available for English and Hindi only.
- Live-verified end-to-end against a real Gnani account: real-time speech-to-text transcription and text-to-speech synthesis both confirmed working.
- As with every other cloud provider, `GNANI_API_KEY` is read only from the environment or `~/.veriturn/.env`, is never persisted or logged, and a Gnani failure never silently falls back to another engine — it surfaces to the tester directly.
- No database migration, no new dependency, no change to existing local/offline providers.

## v2.2.0 — 2026-07-09

- Improves the Responsible AI testing report for senior-management review: clearer report titling, cleaner program/provider metadata, management-ready "How to read this report" guidance, refined coverage/verdict presentation, and language-level testing commentary outside dense tables.
- Test Program Findings now support richer analyst-style LLM drafts that are grounded in program rollups and session transcripts, while remaining human-reviewed before export.
- Evidence Review and report exports include cleaner timeline/report presentation for audit packages, including clearer audio-path placement and improved JSON handling during report drafting.
- Every release asset (app tarball, CPU/CUDA runtime tarballs) is verified by SHA-256 against `RELEASE_MANIFEST.json` before and after install.
