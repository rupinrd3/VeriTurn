# Release Notes

## Current Private Release

- Core processing logic has been improved and hardened for adversarial UAT workflows, providing more robust state verification signals and streamlined tester steering feedback.

- Every release asset (app tarball, CPU/CUDA runtime tarballs) is verified
  by SHA-256 against `RELEASE_MANIFEST.json` before and after install.

For upgrade-time behavior and rollback limits, see `docs/upgrade.md`. For
the full historical changelog once subsequent versions ship, see
`docs/release_notes_archive.md`.
