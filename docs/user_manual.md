# User Manual

This is the release-specific user manual, identical in content to
`../USER_MANUAL.md` at the repo root (kept here as well so the `docs/`
folder is self-contained). It does not require access to the development
repository.

## Intended use

Permitted use is limited to internal evaluation, UAT, and testing of
authorized voice-bot workflows against your organization's own test numbers
and test personas. It must not be used for production collections, bulk
dialing, autonomous customer-calling campaigns, or contacting real customers
unless separately authorized and legally compliant. See `../LICENSE.txt` for
the full terms. VeriTurn never dials, ends a call, or speaks without your
explicit human approval.

## 1. Install

```bash
scripts/setup_ubuntu.sh
```

See `installation.md` for the full flow and `hardware_readiness.md` for
Bluetooth/ADB/GPU/model prerequisites. Ubuntu 22.04+/x86_64 is the first
certified target.

## 2. Launch

```bash
scripts/launch_veriturn.sh
```

Sets the release runtime environment (`VERITURN_HOME`, `VERITURN_RUNTIME_DIR`,
`VERITURN_MODEL_DIR`, `LD_LIBRARY_PATH`) and starts the installed app binary.

## 3. First-run checks

Open **Settings**, then run **Setup Check** (validates ADB, audio route,
STT/LLM/TTS engines, storage, recording authorization individually) and
**Global Health Check** (the same authoritative gate real-call start uses).
Configure cloud provider keys first if you plan to use one — see
`cloud_provider_keys.md`.

## 4. Normal use

1. **Device Status** — confirm the Android test phone's ADB/Bluetooth state.
2. **Scenario Library** — review risk objectives, personas, language variants.
3. **Test Setup** — choose service/language/objective/persona, or resume a
   Test Program's planned combination matrix.
4. **Live Call Console** — place the call once readiness is green; every
   response option is shown to you before use, and you can end the call at
   any point.
5. **Evidence Review** — review transcript/audio/translation/judge
   suggestion, then record your own authoritative human verdict.
6. **Test Program tabs** (Summary / Analysis / Report) — coverage,
   guardrail pass rates, human-vs-judge agreement, critical-failure
   register, and compliance report export.

## 5. Evidence and reports

Written under `~/.veriturn/evidence/`; program exports (including the
compliance report and a checksummed chain-of-custody manifest) land under
`~/.veriturn/evidence/exports/programs/<program_id>_<timestamp>/`. See
`file_layout.md`.

## 6. Upgrading

```bash
git pull
scripts/setup_ubuntu.sh
```

Only app/runtime binaries are replaced; models, database, evidence,
backups, and `.env` are preserved, and a database backup is taken
automatically first. See `upgrade.md` for rollback limits.

## 7. Troubleshooting and support

See `troubleshooting.md`. Before escalating, capture the output of
`scripts/check_ubuntu_audio.sh` and `scripts/setup_ubuntu.sh --verify`,
along with your installed app version (`~/.veriturn/app/APP_VERSION`) and
runtime variant (`~/.veriturn/app/RUNTIME_VARIANT`) — never include API key
values or evidence content in a support request.

## Further reading

- `installation.md`, `hardware_readiness.md`, `cloud_provider_keys.md`,
  `upgrade.md`, `file_layout.md`, `troubleshooting.md`
- `../LICENSE.txt` — permitted use terms
