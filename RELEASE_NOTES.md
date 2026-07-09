# Release Notes

## Current Private Release

- Version 2.2.0 improves the Responsible AI testing report for senior-management review: clearer report titling, cleaner program/provider metadata, management-ready "How to read this report" guidance, refined coverage/verdict presentation, and language-level testing commentary outside dense tables.

- Test Program Findings now support richer analyst-style LLM drafts that are grounded in program rollups and session transcripts, while remaining human-reviewed before export.

- Evidence Review and report exports include cleaner timeline/report presentation for audit packages, including clearer audio-path placement and improved JSON handling during report drafting.

- Every release asset (app tarball, CPU/CUDA runtime tarballs) is verified
  by SHA-256 against `RELEASE_MANIFEST.json` before and after install.

For upgrade-time behavior and rollback limits, see `docs/upgrade.md`. For
the full historical changelog once subsequent versions ship, see
`docs/release_notes_archive.md`.
