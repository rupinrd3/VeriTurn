# Troubleshooting

All paths below are release paths under `~/.veriturn` (see `file_layout.md`),
not development repo paths.

## Installation

- **`gh` not authenticated** — `gh auth status --hostname github.com`, then
  `gh auth login --hostname github.com` if it reports not logged in.
- **SHA-256 mismatch during install** — the download was interrupted or
  corrupted. Delete `~/.veriturn/downloads/<version>` and re-run
  `scripts/setup_ubuntu.sh`.
- **"Staged app binary is missing or not executable"** — the app tarball
  did not extract as expected; re-run the installer. If it persists, delete
  `~/.veriturn/staging/<version>` first.
- **"Refusing downgrade"** — see `upgrade.md`; restore a matching database
  backup from `~/.veriturn/backups/` before installing an older version.
- **Unsupported architecture / Ubuntu version** — this release targets
  Ubuntu 22.04+ on x86_64 only; the installer exits early with this message
  on anything else.

## Runtime tools / models

- **Runtime tool dependency failure** — run
  `scripts/verify_release_assets.sh RELEASE_MANIFEST.json .` and check which
  binary/library path it reports. A dangling shared-library symlink or
  missing CUDA overlay is the usual cause; re-run the installer. Launch the
  app with `scripts/launch_veriturn.sh`; it sets the loader path for both
  `runtime/lib` and `runtime/bin`.
- **Custom `VERITURN_HOME` still writes to `~/.veriturn/db`** — start the app
  through `scripts/launch_veriturn.sh`. For custom install roots the launcher
  creates `$VERITURN_HOME/.home-shim/.veriturn` as a symlink back to the
  selected root and runs the app with that shim as `HOME`, keeping the database
  under `$VERITURN_HOME/db/app.sqlite`.
- **"No usable NVIDIA GPU detected" but you have one** — confirm
  `nvidia-smi -L` runs successfully outside VeriTurn first (driver/kernel
  module issue); or pass `--force-cuda` to install the overlay anyway once
  the driver is fixed.
- **Missing models on first launch** — Setup Check fails because a selected
  STT/TTS/LLM model file is not present. Either let the installer's default
  model download run (don't pass `--skip-models`), run
  `scripts/download_default_models.sh` manually, place the larger/gated
  models listed in `hardware_readiness.md` under `~/.veriturn/models/`, or
  select a cloud provider in Settings instead.

## Bluetooth / call audio

- **No Bluetooth call audio nodes in PipeWire** — HFP call-audio nodes only
  appear *during an active phone call* with audio explicitly routed to this
  PC; pairing alone is not enough. Start a test call, route audio to this
  computer, then check with `scripts/check_ubuntu_audio.sh`.
- **Bluetooth service not active** —
  `sudo systemctl start bluetooth && sudo systemctl enable bluetooth`.
- **WirePlumber Bluetooth config missing** — re-run
  `scripts/setup_ubuntu.sh` (it only writes the config if none exists yet),
  then `systemctl --user restart wireplumber pipewire pipewire-pulse`.

## ADB / phone control

- **ADB unauthorized** — enable USB debugging on the Android test phone
  (Settings → About Phone → tap Build Number 7 times → Developer Options →
  USB Debugging: ON), connect via USB, and accept the desktop authorization
  prompt on the phone. Confirm with `adb devices`.
- **ADB device not listed at all** — check the USB cable/port supports data
  (not charge-only), and that `adb` is installed
  (`sudo apt install -y adb`).

## Cloud providers

- **Cloud key missing/invalid** — add the key to `~/.veriturn/.env`, never
  paste it directly into evidence, reports, or logs. See
  `cloud_provider_keys.md`.
- **Cloud STT readiness probe fails** — the shipped fixture at
  `~/.veriturn/app/data/probes/nvidia_stt_probe_en.wav` is used by default;
  restore it from a fresh install if deleted, or set
  `VERITURN_NVIDIA_STT_PROBE_WAV` / `VERITURN_SARVAM_STT_PROBE_WAV` to a
  short 16 kHz mono WAV of your own.

## Fonts

- **Indic scripts render as boxes in the transcript** — install Noto fonts:
  `sudo apt install -y fonts-noto fonts-noto-core fonts-noto-ui-core fonts-noto-extra`.

## Still stuck?

Run `scripts/check_ubuntu_audio.sh` and `scripts/verify_release_assets.sh`
and capture their output before contacting support — see the "Support
handoff" section in `USER_MANUAL.md`.
