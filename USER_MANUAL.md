# VeriTurn Studio User Manual

VeriTurn Studio is a single-user desktop application for **semi-assisted, human-in-the-loop Responsible AI (RAI) User Acceptance Testing (UAT)** of collections voice bots. The application places the human tester in absolute control of the call: it coordinates phone calls, transcribes bot speech, generates persona-grounded response options, and synthesizes speech—but it **never places calls, ends calls, or speaks without your explicit manual approval**.

This manual provides detailed instructions on downloading, installing, configuring, troubleshooting, and executing test programs screen-by-screen.

---

## 1. Intended Use & Safety Boundaries

### Intended Use
VeriTurn Studio is designed strictly for UAT, compliance stress-testing, and model risk assessment of automated voice systems. It must only be used to call test phone numbers configured for UAT and connected to synthetic automated agents (vendor bots).

### Safety Guardrails
*   **No Customer Contact:** Do not use this software to call real customers, run actual collection campaigns, or automate dialing for business operations.
*   **Human-in-the-Loop Constraint:** The synthetic customer (the AI response model) cannot dial or hang up autonomously. Every spoken response must be approved or manually typed by the tester before synthesis.
*   **Data Privacy:** All recording, turn history, and evaluation evidence are stored locally on your machine. API keys for optional cloud providers are read only from your environment or `~/.veriturn/.env` and are never embedded in the database, log streams, or exported evidence.

---

## 2. Obtaining the Software & Clone Guide

VeriTurn Studio is distributed via a private GitHub release repository (`https://github.com/rupinrd3/VeriTurn.git`). Access is collaborator-restricted.

### Prerequisites
1.  Ensure your GitHub account has been added as a collaborator to the private `rupinrd3/VeriTurn` repository.
2.  Install and authenticate the GitHub CLI (`gh`) on your machine:
    ```bash
    # Login and follow the browser/token authentication prompts
    gh auth login --hostname github.com
    ```

### Cloning the Release Repository
Run the following commands to clone the release files:
```bash
# Clone the release repository containing scripts and documentation
git clone https://github.com/rupinrd3/VeriTurn.git veriturn_release
cd veriturn_release
```
*Note: The release repository does not contain large application binaries or voice model files in its git history. These are attached to GitHub Releases and are fetched dynamically by the installer script.*

---

## 3. Installation & System Setup

Ubuntu 22.04+ (x86_64) is the certified target operating system. Ensure your system meets the hardware requirements (Bluetooth capability for call audio routing and an Android device for dialer coordination).

### Step 1: Install System Dependencies
Install the required packages for device control, audio routing, and multi-language Indic font rendering:
```bash
sudo apt update
sudo apt install -y adb bluez pipewire wireplumber \
  fonts-noto fonts-noto-core fonts-noto-ui-core fonts-noto-extra
```

### Step 2: Run the Setup Installer
After a fresh clone or `git pull`, run the installer script:
```bash
./scripts/setup_ubuntu.sh
```

#### What the Installer Does:
1.  **Directory Creation:** Sets up the application structure under your home directory:
    *   `~/.veriturn/app/` — Application executable binaries and public metadata.
    *   `~/.veriturn/runtime/` — Local sidecar executables (`llama-server`, `whisper-server`, `piper`).
    *   `~/.veriturn/models/` — Subfolders for LLM GGUF models, STT binaries, and TTS voice files.
    *   `~/.veriturn/db/` — Local SQLite databases.
    *   `~/.veriturn/evidence/` — Saved audio recordings, transcripts, and export folders.
    *   `~/.veriturn/backups/` — Automatic database backups prior to upgrades.
2.  **GPU Detection:** Queries `nvidia-smi` to detect an NVIDIA GPU. If found, it installs the CUDA sidecar libraries for hardware-accelerated speech-to-text and response generation. If no GPU is found, it installs a lightweight CPU-only runtime bundle.
3.  **Asset Verification:** Downloads the release archives from the private GitHub Releases section only when the installed app/runtime binaries are missing or stale, and verifies their SHA-256 integrity signatures against the repository's `RELEASE_MANIFEST.json`.
4.  **Audio Configuration:** Configures WirePlumber policy templates to automatically route Bluetooth HFP calls (Hands-Free Profile) to the system audio capture engine.
5.  **Model Downloads:** Fetches the default Whisper STT model and standard Piper TTS voices (~350 MB total) so the system is ready to run basic sessions out of the box.
6.  **Environment template:** Initializes a template `.env` file under `~/.veriturn/.env`.

### Step 3: Verify the Installation
To verify that all files are in place and intact without executing a full reinstall, run:
```bash
./scripts/setup_ubuntu.sh --verify
```

---

## 4. Post-Install Environment Configuration

### Directory Layout Map
Ensure your model directories are populated appropriately:
*   **LLM Models (`~/.veriturn/models/llm/`):** Put GGUF format LLM models here (e.g., Qwen-3 or Llama-3-8B) if you intend to run local text generation.
*   **STT Models (`~/.veriturn/models/stt/`):** Whisper GGML binaries (e.g., `ggml-small.en.bin`) go here.
*   **TTS Voice Files (`~/.veriturn/models/tts/`):** Piper voice `.onnx` and `.onnx.json` config pairs are stored here.
*   **Translation Models (`~/.veriturn/models/translation/`):** Pinned CTranslate2 / IndicTrans2 folders are stored here for offline Indic-to-English translation.

### API Keys and Cloud Configurations
If you choose to use cloud APIs (Gemini, NVIDIA NIM, or Sarvam) instead of local hardware inference:
1.  Open `~/.veriturn/.env` in a text editor.
2.  Provide your API keys in the appropriate fields:
    ```env
    # API Keys for Cloud Processing (Optional)
    GEMINI_API_KEY=your_gemini_api_key_here
    NVIDIA_API_KEY=your_nvidia_nim_api_key_here
    SARVAM_API_KEY=your_sarvam_api_key_here
    ```
3.  Save the file. VeriTurn Studio loads these values directly into the runtime memory; they are never persisted to databases or written to UAT evidence logs.

---

## 5. Setup Troubleshooting

### GitHub CLI Authentication Errors
*   **Problem:** The installer fails with `gh release download: authorization failed` or similar permissions errors.
*   **Resolution:** You must have collaborator access granted to `rupinrd3/VeriTurn`. Test your credentials by running `gh repo view rupinrd3/VeriTurn` in the terminal. If it fails, verify you are logged in to the correct GitHub account. Run `gh auth login` again.

### Shared Library Missing Errors (`ldd` checks fail)
*   **Problem:** The installer warns that some runtime sidecar binaries are missing dependencies.
*   **Resolution:** Ensure your system is updated and standard development libraries are installed. On Ubuntu, run:
    ```bash
    sudo apt install -y build-essential libasound2-dev libpulse-dev
    ```
    If GPU acceleration is enabled, confirm your NVIDIA drivers are correctly configured and that the output of `nvidia-smi` displays your card correctly.

### Audio Diagnostic Failures
*   **Problem:** WirePlumber does not detect phone routing paths, or the phone does not route call audio to the computer.
*   **Resolution:** Run the diagnostic helper script:
    ```bash
    ./scripts/check_ubuntu_audio.sh
    ```
    This script inspects running audio servers (PipeWire / PulseAudio), checks if the bluetooth daemon is active, lists available source/sink profiles, and checks if the system's `handsfree` profile is loaded. Ensure your phone is paired using the system's bluetooth settings and that the phone's connection profile has "Phone Calls" enabled.

---

## 6. Launching and Screen-by-Screen Walkthrough

Start the application by running the launch helper script:
```bash
./scripts/launch_veriturn.sh
```
This script launches the Tauri client, bringing up the VeriTurn Studio desktop cockpit window.

---

### Screen 1: Home Dashboard (`home`)
The entry point of the application provides an operational summary.
*   **Key Controls & Layout:**
    *   **Global Health Status Bar:** Located at the top of the interface, this bar shows a real-time summary of the system components. It remains Green only if all core dependencies are functional.
    *   **Test Statistics Cards:** Display total sessions run, active test programs, overall pass/fail ratios, and pending evaluations.
    *   **Quick Rails:** Fast navigation links to create a new session, jump to the Scenario Library, or resume the last active Test Program.

---

### Screen 2: Setup Check (`setup-check`)
This screen provides a detailed status checklist for every subsystem.
*   **Layout:** A table displaying the status of 6 key readiness categories:
    1.  **ADB Connection:** Verifies Android USB connectivity.
    2.  **Audio Routings:** Checks Bluetooth HFP call channels and PipeWire endpoints.
    3.  **Inference Engine sidecars:** Assures that `llama-server`, `whisper-server`, and `piper` are running on their assigned ports.
    4.  **Storage Access:** Verifies write permissions to databases and evidence storage.
    5.  **Recording Authorization:** Checks OS-level microphone access.
    6.  **API Configurations:** Confirms cloud token formats inside `.env`.
*   **Key Controls:**
    *   **Refresh Check:** Triggers a fresh scan of all subsystems.
    *   **Actionable Error Panels:** If a check is Red (Blocked), clicking on the row expands instructions detailing the exact command or file copy needed to resolve the blocker.

---

### Screen 3: Service Providers (`providers`)
Manage the target voice systems (Services Under Test) that you intend to call.
*   **Layout:** A grid of configured voice-bot profiles showing the vendor's name, primary test number, and target descriptions.
*   **Key Controls:**
    *   **Add Provider:** Opens a form to define a new target with fields for name, test phone number, default spoken language, and operational notes (e.g., target IVR menu paths).
    *   **Edit / Remove:** Modifies provider phone numbers or deletes stale test targets.

---

### Screen 4: Scenario Library (`scenario-library`)
Explore and select the testing templates that dictate the customer's behavior and the compliance criteria.
*   **Layout:** Split into two tabs:
    1.  **Risk Objectives Tab:** Displays cards for the 12 built-in compliance test plans (e.g., *Privacy Disclosures*, *Harassment Boundaries*, *Hardship Identification*). Each card displays the expected bot actions, forbidden actions, and critical failure keywords.
    2.  **Personas Tab:** Shows the 20 built-in synthetic customer characters (e.g., *Anxious Delayer*, *Aggressive Denier*, *Concerned Spouse*). Displays their emotional profiles and behavioral limits.
*   **Key Controls:**
    *   **Launch Ad-Hoc Session:** Click on any combination of Risk Objective and Persona to launch a one-off session immediately without program overhead.

---

### Screen 5: Test Programs (`test-runs`)
Manage structured UAT cycles consisting of multiple test scenarios and runs.
*   **Layout:**
    *   **Programs Rail:** A list on the left side of the screen displaying created programs.
    *   **Combinations Tab:** A grid displaying the planned combinations of Language × Risk Objective × Persona. Each cell shows a progress count (e.g., `Done: 2/3`).
    *   **Summary Tab:** Aggregates overall program statistics, generating a heatmap grid of pass rates sorted by risk objective and language.
*   **Key Controls:**
    *   **New Program Form:** Create a UAT program, define its scope, objective list, and repetition counts.
    *   **Matrix Configuration:** Add/remove cells from the planned testing matrix.
    *   **Start Attempt:** Selects a cell and transitions to the Live Console to run that specific combination attempt.
    *   **Rerun / Detach:** If a call fails due to connection loss or tester error, this button detaches the active session and spawns a fresh attempt, preserving the previous run's data as superseded evidence.

---

### Screen 6: Live Test Console (`live-test-console`)
The core operational cockpit of the application. It becomes active only when a call session starts.
*   **Layout:**
    *   **Call Control Panel:** Standard controls to start, mute, and terminate the session.
    *   **Active Timeline:** A scrollable list displaying the conversation turn-by-turn. Each turn is marked with its source (Vendor Bot, Synthetic Customer, or Manual Override).
    *   **Move Classifier Panel:** Displays detected bot moves (e.g., "ID Verification", "Insistent Demand") matched against the bot-move taxonomy.
    *   **Response Generation Area:** Displays response options generated by the LLM based on the active customer persona and the steering guidelines.
*   **Key Controls:**
    *   **Initiate Call (ADB Dial):** Sends a secure command to your connected Android phone to dial the target provider's test number.
    *   **Regenerate Options:** Requests the active LLM to generate a new set of response options.
    *   **Edit Input Field:** Allows the tester to edit any generated response option or type a completely custom reply.
    *   **Speak Button (Manual Approval Gate):** Processes the selected text through the TTS engine and speaks it into the call stream. **No audio is sent to the call until the tester clicks this button.**
    *   **Add Issue Panel:** Logs a compliance violation mid-call. Testers select a category, assign a severity (Minor, Major, or Critical), and type descriptive notes.
    *   **End Session:** Hangs up the call and transitions the tester to the Evidence Review Screen.

---

### Screen 7: Evidence Review (`evidence-review`)
Perform post-call analysis, audit the transcript, verify translations, and log the official UAT results.
*   **Layout:**
    *   **Audio Waveform Panel:** Visualizes the full call audio recording. Includes playback speed sliders and skip-turn markers.
    *   **Attributed Transcript:** Displays the bilingual turn log. Non-English turns show the original text side-by-side with their English translation.
    *   **Issue Register:** Lists all mid-call flagged issues.
    *   **Human Evaluation Panel:** Displays the official UAT verdict selection (Pass, Fail, Needs Review, Inconclusive).
*   **Key Controls:**
    *   **Issue Confirm / Reject:** Allows the UAT analyst to confirm or reject flagged violations.
    *   **Edit Issue Severity:** Promotes or demotes the severity level of confirmed issues.
    *   **Save Evaluation:** Records the analyst assessment and logs the final verdict.
    *   **Offline Jobs Manager:** Displays the queue status of offline translation processes and the advisory LLM-as-a-Judge execution. Click "Retry" to restart any failed offline jobs.

---

### Screen 8: Settings Manager (`settings`)
Configure inference engines, thresholds, and path options.
*   **Layout & Key Fields:**
    *   **STT Engine Settings:** Choose the Speech-to-Text provider (Local Whisper, Local Nemotron, or cloud APIs). Adjust the VAD (Voice Activity Detection) energy threshold to fine-tune silence detection.
    *   **LLM Provider Settings:** Set default models (e.g., Local Qwen GGUF or Cloud Gemini/NVIDIA templates).
    *   **TTS Voice Selection:** Select voice files per language from the manifest.
    *   **Offline Translators:** Select the active translation engine (CTranslate2 offline or Cloud equivalents).
    *   **Directory Paths:** Points to your model files under `~/.veriturn/models`.

---

## 7. Operational Troubleshooting

### Android USB / ADB Connection Loss
*   **Problem:** The Live Console displays `ADB_DISCONNECTED` or does not register the device when plugged in.
*   **Resolution:**
    1.  Ensure USB Debugging is enabled on the phone (Settings → Developer Options → USB Debugging).
    2.  Unlock the phone and look for the dialog prompt: "Allow USB Debugging?". Tick "Always allow" and tap Accept.
    3.  Confirm connection in the terminal:
        ```bash
        adb devices
        ```
        If the device is listed as `unauthorized`, unplug the cable, restart the adb server (`adb kill-server && adb start-server`), and reconnect the cable.

### Bluetooth Call Audio Routing Issues
*   **Problem:** The phone dials, but call audio is not captured by VeriTurn.
*   **Resolution:**
    1.  Confirm the phone is connected over Bluetooth HFP (Hands-Free Profile), not A2DP (music profile).
    2.  Open your system volume control (e.g., PulseAudio Volume Control or your desktop system settings) and verify that the Bluetooth phone appears as a recording source and playback sink.
    3.  During active calls, the OS creates transient call audio streams. If they are routed incorrectly, open terminal and run `./scripts/check_ubuntu_audio.sh` to restart the WirePlumber policy router.

### STT Gating and Hallucination Problems
*   **Problem:** Whisper transcribes silent periods as hallucinated phrases, or fails to segment speech correctly.
*   **Resolution:**
    1.  Navigate to **Settings → STT Engine Settings**.
    2.  If Whisper is hallucinating words during silence, increase the **VAD Energy Threshold** slider slightly (e.g., from `0.02` to `0.05`) to prevent low-level noise from triggering STT passes.
    3.  Verify the Whisper GGML model path in settings matches the file on disk.

### Local LLM Engine Out of Memory (OOM)
*   **Problem:** The local `llama-server` process crashes or fails to respond when generating responses.
*   **Resolution:**
    1.  Check the size of the GGUF model you placed under `~/.veriturn/models/llm/`. Ensure it fits comfortably within your machine's system RAM / VRAM.
    2.  If using GPU acceleration, verify that your GPU memory is not exceeded. A 7B or 8B parameter model quantized to `Q5_K_M` (approx. 5 GB) is recommended for 8 GB VRAM cards.
    3.  Restart the sidecar from the terminal if it is stuck:
        ```bash
        pkill -f llama-server
        ```

### Offline Translation Queue Stuck
*   **Problem:** Translating Indic language turns to English is stuck in "Pending" status on the Evidence Review screen.
*   **Resolution:**
    1.  Offline translation jobs are designed to pause automatically while a live call session is active to prevent resource contention. Ensure all active calls are fully ended.
    2.  If the queue remains stuck, check the offline worker status in Settings, or run the following command to check running sidecars:
        ```bash
        pgrep -f ct2
        ```
    3.  Use the **Retry** button in the Evidence Review offline jobs panel to trigger a clean sweep of the queue.
