# Agentic VOIP release verification

The packaged Agentic runner is a local, Rust-supervised runtime component. It
does not contain credentials and it must never be exposed directly to the
internet: only a tester-configured cloudflared tunnel may expose the approved
provider paths. Control, decision, and telemetry ports remain loopback-only.

Before any manual test, run the matching diagnostic from the development
release-candidate checkout: `scripts/check_agentic_voip.sh` on Ubuntu or
`scripts/check_agentic_voip.ps1` on Windows. These diagnostics are read-only
and redact credentials. They do not contact a provider, tunnel, or phone.

Manual certification requires one explicitly armed call against an approved
exact test number for each Ubuntu/Windows and Twilio/Plivo pair. Record the
date, account alias, Stop/barge-in/tunnel-loss/runner-kill/recovery result, and
a redacted evidence reference in the Slice 67 verification matrix. Until the
relevant row is complete, that platform/provider release claim is blocked.

Never put provider credentials, full phone numbers, run tokens, or spool audio
in this repository or the matrix. There is no automatic redial or provider
failover.
