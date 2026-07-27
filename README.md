# VeriTurn Studio

GenAI voice bots that talk to real customers — for collections, servicing, or support — can fail in ways an ordinary functional test never catches: leaking a third party's debt details to a wrong number, escalating instead of de-escalating an angry caller, mishandling a distress or self-harm disclosure, or quietly drifting into the wrong language mid-call. Most of these bots are also deployed across Indian languages, where compliance and safety testing tooling is thin to begin with. **VeriTurn Studio exists to find these failures before a real customer does** — over an actual phone/VOIP call, not a text-only simulation.

It is a single-user Tauri v2 desktop application for **Responsible AI (RAI) User Acceptance Testing (UAT)** of GenAI voice bots: structured, repeatable adversarial and robustness testing across **Language × Risk Objective × Customer Persona** combinations, producing audit-ready compliance evidence at the end of every call.

It ships with two execution modes, switchable from the sidebar, sharing the same scenario library, providers, evidence model, and reports:

| | **Human mode** (default) | **Agentic AI mode** (opt-in, separately armed) |
|---|---|---|
| Call control | Tester dials/hangs up on the test phone over Bluetooth HFP | Bounded VOIP dialing (Twilio/Plivo), one call at a time |
| Turn approval | Every response is tester-approved before it is spoken | Deterministic Director/Interrogator/`AutoSpeechGate`/`Warden` safety layer validates each turn pre-speech; no unreviewed model line is ever spoken |
| Screen | Live Test Console | Mission Control + Review Queue |
| Best for | Manual, judgment-heavy UAT sessions | Unattended coverage runs across a Test Program matrix |

In **Human mode** it acts as a controlled **synthetic customer cockpit**: it listens to the vendor bot over Bluetooth HFP audio, transcribes speech in 8 languages using local or opt-in cloud STT, classifies the bot's compliance moves, generates persona-grounded response options via local LLM or approved cloud providers, and speaks only tester-approved utterances back into the call via local TTS. In **Agentic AI mode**, the same STT/LLM/TTS pipeline runs end-to-end over VOIP without per-turn approval, gated instead by the deterministic safety layer, and every run lands in a human Review Queue. After a call in either mode, an optional offline LLM-as-a-Judge evaluates the session against the selected Risk Objective's rubric and surfaces an advisory verdict — always subject to human review.

> [!WARNING]
> **CRITICAL SAFETY BOUNDARIES**
> * **Not a Production System:** This tool is strictly for compliance, model-risk, and RAI testing. It must never be used to call real customers, perform actual collections activity, or automate bulk dialing.
> * **Human-in-the-Loop by default:** In Human mode, the tester always manually controls call initiation/termination on the test phone, and **no response is ever spoken without explicit human approval**. Agentic AI mode is a separately armed exception with its own deterministic safety layer — it never removes human authority over verdicts, attestation, or redaction, and never dials more than one call at a time.
> * **Local-first Execution:** All audio recording, STT output, evidence, and the SQLite database remain on your local machine. Approved online cloud providers (Gemini LLM, NVIDIA NIM STT / live LLM / advisory judge / TTS, Sarvam STT/TTS, Gnani Vachana STT/TTS) are explicit opt-in selections in Settings and are disabled by default. API keys are read only from the environment or `~/.veriturn/.env` and are never stored in the database or evidence files.
> * **No Source Access:** This repository ships pre-compiled binaries, user documentation, and setup scripts. The application source code, development tools, and canonical protected prompts/framework files are excluded from this release.

---

## Screenshots

<table>
<tr>
<td width="50%" valign="top">

**Agentic AI — Mission Control**
Live-run monitoring for an unattended VOIP test call: turn-by-turn transcript with system decisions, current test combination, engine telemetry (STT/LLM/TTS route in use), Agentic VOIP health, and a persistent Review Queue / Stop for human oversight.

</td>
<td width="50%" valign="top">

**Human-in-the-loop — Scenario Library & Session Setup**
Selecting a Risk Objective and Customer Profile before a live session: pass/fail criteria, failure signals to watch for, adversarial case file/playbook status, and per-session STT/TTS/provider configuration.

</td>
</tr>
<tr>
<td width="50%"><img src="docs/screenshots/mission-control-agentic.png" alt="Agentic AI Mission Control screen showing a live run's transcript, decisions, engine telemetry, and health status"></td>
<td width="50%"><img src="docs/screenshots/scenario-library-human.png" alt="Human-in-the-loop Scenario Library screen showing risk objectives, customer profiles, and session configuration"></td>
</tr>
</table>

---

## Core Objectives

Generative AI collections voice bots must adhere to strict guidelines (e.g., debt collection laws, harassment restrictions, privacy protections, and language standards). VeriTurn Studio enables compliance and UAT teams to:
1. **Verify Privacy Boundaries:** Test if vendor bots leak customer PII, debt details, or account context to third parties (e.g., wrong-number scenarios or relative probes).
2. **Stress-Test Coercive Conduct:** Evaluate vendor behavior under delay requests, denials of liability, and customer anxiety.
3. **Audit State Transitions:** Ensure the vendor bot responds appropriately when a customer transitions through various postures.
4. **Collect Structured Evidence:** Generate turn-by-turn audit logs, recordings, and issue metadata to document compliance gaps.

---

## Core Architecture: Risk Objectives vs. Personas

VeriTurn Studio decouples **what is being tested** from **how the simulated customer behaves**.

*   **Risk Objective (The Exam Paper):** A compliance objective drawn from the Scenario Library — e.g., "Privacy & disclosure boundary" or "Coercion & delay handling." It defines the pass/fail criteria (Expected vs. Forbidden Vendor Behavior) and specific Critical Failure Triggers. It does *not* represent a specific user.
*   **Customer Profile / Persona (The Actor):** Represents the synthetic customer's emotional state, tone, and communication style (e.g., *Anxious Delayer*, *Concerned Relative*, *Cooperative Borrower*). The persona's behavioral brief is injected into the LLM system prompt at session start.

During a live UAT call:
1.  **AI Response Steering (Active Probing):** The Risk Objective's criteria and failure triggers are fed into the LLM system prompt, guiding the AI simulation to actively probe the vendor bot's boundaries.
2.  **Post-Call Evaluation:** The Risk Objective provides the framework for the human tester to assign a verdict (pass / fail / needs_review / inconclusive) and for the optional advisory LLM-as-a-Judge to surface a suggested verdict.

Sessions can be run as **ad-hoc** (single scenario, launched directly from the Scenario Library) or as part of a **Test Program** (a planned matrix of Language × Risk Objective × Persona combinations with aggregate pass-rate reporting).

---

## Core Features

* **Synthetic Customer Simulation:** 20 built-in customer profiles (e.g., *Anxious Delayer*, *Concerned Relative*, *Sarcastic Jokester*) with distinct tone modifiers, behavioral state machines, and allowed/forbidden move boundaries.
* **12 Risk Objectives:** Scenario Library covers process compliance, privacy boundaries, toxicity, distress/self-harm safety, hardship, coercion, legal threat detection, disputes, harassment, fairness, prompt-injection resistance, and authority accuracy.
* **State Machine & Bot-Move Taxonomy:** Tracks conversation states deterministically. Classifies vendor utterances (e.g., *identity verification*, *payment insistence*) and limits synthetic customer moves to safe, legally compliant boundaries.
* **Energy-Based VAD & STT Gating:** Local Voice Activity Detection (VAD) segments live call audio into utterance windows; Whisper quality-signal filtering (`no_speech_prob`, log probability) removes hallucinated transcriptions before they enter the pipeline.
* **8-Language Support:** English, Hindi, Bengali, Marathi, Telugu, Tamil, Gujarati, and Kannada. The tester selects the call language up front and it is forced for the whole session — STT is never left to auto-detect per segment, which previously caused mid-call language/script drift.
* **Flexible LLM Response Generation:** Local `llama-server` (llama.cpp, default) or opt-in cloud providers (Gemini 3.1 Flash Lite, NVIDIA NIM) for turn-by-turn response generation. All options require explicit tester approval before speaking.
* **Assisted Response & Correction Console:** Human tester approves, edits, regenerates, or manually types responses; flags compliance issues with severity (Minor / Major / Critical) and mandatory notes.
* **Test Program Matrix:** Plan and execute full Language × Risk Objective × Persona coverage matrices with per-combination attempt tracking, rerun support, and aggregate pass-rate heatmaps.
* **Advisory LLM-as-a-Judge:** Optional post-session AI evaluation (local llama.cpp, Gemini, or NVIDIA NIM) applies a per-criterion rubric against the transcript — verdict is advisory only; human verdict is always authoritative.
* **Offline Translation:** Background translation of non-English turns to English (local LLM, Gemini, or native CTranslate2 + IndicTrans2), with per-turn retry and bilingual evidence export.
* **Audit-Ready Evidence Export:** UAT evidence bundles (JSON, Markdown, CSV, per-turn WAV, and a full-call recording) at the session level; program-level consolidated reports with coverage heatmap, guardrail comparison, and trend analysis.
* **Hardware & Audio Diagnostics:** Per-subsystem readiness checks for ADB, Bluetooth HFP, PipeWire audio routing, and all sidecar processes — with actionable status messages for every BLOCKED condition.

---

## Agentic AI VOIP Mode

Alongside Human mode, this release includes a separately armed **Agentic AI** execution mode that runs one authorized test call at a time over VOIP (Twilio/Plivo) without per-turn human approval. It is opt-in, bounded, and does not change Human mode, which remains the default on every launch.

* **One-call invariant:** never more than one call or program run active at a time — no bulk dialing, no autonomous redial, no production customer calling.
* **Deterministic safety layer:** a Director/Interrogator decision layer, an `AutoSpeechGate`, and a terminal `Warden` policy govern every autonomous turn, producing one of a fixed outcome vocabulary (`bot_resisted`, `objective_achieved`, `objective_achieved_unvalidated`, `execution_blocked`, `technical_failure`, `stopped_by_user`).
* **Mission Control & Review Queue:** a live-run screen shows the transcript, system decisions, current test combination/progress, and per-engine (STT/LLM/TTS) telemetry as a run executes unattended; every completed run lands in a Review Queue for human verdict, attestation, and redaction — Agentic AI never assigns its own final verdict.
* **Engine parity with Human mode:** the same local/cloud STT, LLM, and TTS engine selection available in Human mode is available to Agentic runs, with the same readiness checks and provider behavior.
* **Local voice runner:** an ephemeral, Rust-supervised local media process handles only real-time Twilio/Plivo media mechanics; a tester-configured Cloudflare Tunnel exposes only signed media/callback routes and must never be exposed to the internet otherwise. Control, decision, and telemetry ports remain loopback-only.

Manual certification of live Twilio/Plivo calls is a per-account, per-platform process — see `docs/agentic_voip_verification.md` before arming a test number. No API key is ever persisted, logged, or exposed in evidence exports or report content, and a runtime failure never silently switches providers or engines.

---

## Release Architecture & Technology Stack

As a pre-packaged release, VeriTurn Studio runs within a protected local runtime environment. The source code is compiled, and sensitive static application logic (prompts, persona definitions, risk objectives, compliance rubrics) is embedded securely in the native binary.

### Shipped Components
* **Tauri Desktop Shell:** Minified and compiled client bundle containing the React + TypeScript frontend and the Rust audio routing engine.
* **SQLite Database:** Local data repository initialized under `~/.veriturn/db/` via versioned migrations.
* **Tauri Sidecar Manager:** Rust process controller managing local sidecars:
  * **LLM Engine:** Local `llama-server` (llama.cpp) running on port 8080.
  * **STT Engine:** Local `whisper-server` (whisper.cpp) running on port 8081 for English/Hindi.
  * **TTS Engine:** Local `piper-tts-server` running on port 8082 for English/Hindi speech.
  * **Indic STT/TTS:** `sherpa-onnx-offline` and `sherpa-onnx-offline-tts` for Indic speech processing.
  * **Translation Engine:** Offline `veriturn-ct2-translate` for translating Indic language transcripts to English.
* **Agentic Voice Runner (opt-in):** an ephemeral, Rust-supervised local media runner plus a tester-configured Cloudflare Tunnel binary, used only when Agentic AI mode is armed for a Twilio/Plivo VOIP call.

---

## Installation & Quick Start

Ubuntu 22.04+ (x86_64) is the certified installation target. Windows support is not available in this release.

### 1. Prerequisites
Before installing, ensure you have collaborator access to this private release repository, and that your local GitHub CLI (`gh`) is installed and authenticated:
```bash
gh auth login --hostname github.com
```

Ensure necessary host packages are installed for phone control, Bluetooth routing, and Indic rendering:
```bash
sudo apt update
sudo apt install -y adb bluez pipewire wireplumber \
  fonts-noto fonts-noto-core fonts-noto-ui-core fonts-noto-extra
```

### 2. Run the Installer
After each `git pull`, run the setup script:
```bash
scripts/setup_ubuntu.sh
```
This script reads the checked-out `APP_VERSION` / `RELEASE_MANIFEST.json`,
downloads the exact app and runtime binaries when they are missing or stale,
verifies their integrity, sets up directories under `~/.veriturn`, downloads
default open-license models, and configures PipeWire audio routing roles.

### 3. Upgrading the Application
To upgrade the application to a specific version (such as `v2.2.0`), you can specify the target version explicitly with the `--version` or `--upgrade` flag:
```bash
scripts/setup_ubuntu.sh --version v2.2.0
```
This will fetch the release manifest and required assets for that version from GitHub, back up your local SQLite database automatically, and safely install the upgrade without overwriting your local API keys or models.

### 4. Launch
Launch the application using the setup-provided script:
```bash
scripts/launch_veriturn.sh
```

---

## Documentation Index

Please consult the following documents inside this release repository:
*   **[USER_MANUAL.md](USER_MANUAL.md)** — Complete step-by-step user manual, screen layout descriptions, keyboard shortcuts, and troubleshooting.
*   **[docs/installation.md](docs/installation.md)** — Quick installation reference.
*   **[docs/hardware_readiness.md](docs/hardware_readiness.md)** — Bluetooth HFP, ADB, GPU, and offline model folder layouts.
*   **[docs/cloud_provider_keys.md](docs/cloud_provider_keys.md)** — Environment variable configuration for Gemini, NVIDIA NIM, Sarvam, and Gnani Vachana.
*   **[docs/file_layout.md](docs/file_layout.md)** — Directory layout reference for `~/.veriturn/`.
*   **[docs/upgrade.md](docs/upgrade.md)** — Upgrade guidelines and database migration restrictions.
*   **[docs/troubleshooting.md](docs/troubleshooting.md)** — Troubleshooting guide for common setup and runtime issues.

Maintainers publish release assets with `scripts/upload_release_assets.sh`
after `scripts/export_release_repo.sh` has populated this repository.
*   **[RELEASE_NOTES.md](RELEASE_NOTES.md)** — Release notes and changes for the current version.
*   **[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)** — Open source license attribution for embedded components.

---

## Credits

VeriTurn Studio was conceived, designed, and built from the ground up by **Rupin Desai** (rupinrd3@gmail.com).

### Contributors

| Name | Email |
|---|---|
| Sanjeev Kumar | sanjeevailead@gmail.com |
