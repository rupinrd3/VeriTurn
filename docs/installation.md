# Installation

This guide covers installing VeriTurn Studio from private GitHub Releases on
Ubuntu 22.04/24.04, x86_64. VeriTurn Studio is for authorized Responsible AI
UAT of voice-bot workflows only — see `LICENSE.txt`.

## 1. Prerequisites

- Collaborator access to the private GitHub release repository.
- GitHub CLI (`gh`), authenticated:

  ```bash
  gh auth login --hostname github.com
  ```

- `python3`, `tar`, `sha256sum`, `ldd` (all present on a standard Ubuntu
  install; the installer checks for each and tells you what package to add
  if one is missing).
- The following runtime packages for phone control, call audio, and Indic
  script rendering:

  ```bash
  sudo apt update
  sudo apt install -y adb bluez pipewire wireplumber \
    fonts-noto fonts-noto-core fonts-noto-ui-core fonts-noto-extra
  ```

  The installer warns (does not block) if any of these are missing, since
  you can still install and use VeriTurn without full hardware readiness and
  fix it before your first live call.

## 2. Install

```bash
scripts/setup_ubuntu.sh
```

After a `git pull`, the installer reads `APP_VERSION` /
`RELEASE_MANIFEST.json` from this release repository and installs the exact
matching GitHub Release assets. You can still pin a release explicitly with
`--version vX.Y.Z` when support asks you to.

What this does, in order:

1. Creates `~/.veriturn/{app,runtime,models,db,evidence,backups,downloads,staging,logs}`.
2. Checks required host tooling and prints guidance for anything missing.
3. Detects your CPU/GPU (`nvidia-smi`) to decide whether to also download the
   CUDA runtime overlay — see "GPU acceleration" below.
4. Confirms OS/architecture support (Ubuntu 22.04+ baseline, x86_64 only).
5. Downloads the release manifest, the app tarball, and the runtime tarball(s)
   from GitHub Releases via `gh release download`, verifying every asset's
   SHA-256 against `RELEASE_MANIFEST.json` before anything is installed.
   Existing app/runtime binaries are skipped only when the installed asset
   metadata matches this manifest and the CPU/CUDA runtime variant.
6. Stages the release, sanity-checks the binary (`ldd`), backs up any
   existing database, then atomically swaps `app/` and `runtime/` into place.
7. Re-verifies the installed files with `scripts/verify_release_assets.sh`.
8. Guides Bluetooth HFP pairing and writes the WirePlumber Hands-Free role
   config (both the 0.5+ `.conf` and 0.4.x Lua config formats are supported).
9. Checks ADB/USB debugging status for your Android test phone.
10. Downloads the default open-license STT/TTS models (Whisper `small.en` +
    four Piper English/Hindi voices, ~350 MB total) unless `--skip-models`
    is passed.
11. Creates `~/.veriturn/.env` with a commented API-key template if it does
    not already exist.
12. Prints a final status summary of every component above.

## 3. GPU acceleration (optional)

The installer detects an NVIDIA GPU via `nvidia-smi -L` and automatically
downloads a CUDA runtime overlay (~450 MB) for GPU-accelerated local
inference; machines without a usable GPU/driver get the smaller CPU-only
bundle (~30–65 MB) instead. Override the auto-detection with `--force-cpu`
or `--force-cuda` if needed. See `hardware_readiness.md` for details.

## 4. Default and additional models

Whisper `small.en` and four Piper English/Hindi voices are downloaded
automatically so Setup Check passes on first launch without a manual model
hunt. Larger or gated models (Nemotron ONNX, sherpa Indic STT/TTS, offline
translation, a local LLM GGUF) remain user-installed — see
`hardware_readiness.md` for exact paths, or select a cloud provider (Gemini,
NVIDIA NIM, Sarvam) in Settings instead of a local model.

## 5. Launch

```bash
scripts/launch_veriturn.sh
```

Then open **Settings → Setup Check** and **Global Health Check** to confirm
every dependency (ADB, audio route, STT/LLM/TTS engines, storage, recording
authorization) is ready before starting a live call.

## 6. Verify an install without reinstalling

```bash
scripts/setup_ubuntu.sh --verify
```

Re-checks every installed file's SHA-256 against the manifest without
downloading or changing anything.

## Command reference

```text
scripts/setup_ubuntu.sh [options]
scripts/setup_ubuntu.sh --version vX.Y.Z [options]
scripts/setup_ubuntu.sh --upgrade vX.Y.Z [options]
scripts/setup_ubuntu.sh --verify
scripts/setup_ubuntu.sh --help

Options:
  --version vX.Y.Z
                 Install this exact release instead of the git-pulled repo version.
  --skip-models   Do not download the default open-license STT/TTS models.
  --force-cpu     Install the CPU-only runtime bundle even if an NVIDIA GPU is detected.
  --force-cuda    Install the CUDA runtime overlay even if no NVIDIA GPU is detected.
```

For upgrades see `upgrade.md`; for hardware/Bluetooth/ADB diagnostics see
`hardware_readiness.md`; for problems see `troubleshooting.md`.

## Maintainer Upload

After the development export has populated this release repository and the
local assets are present, maintainers publish them with:

```bash
scripts/upload_release_assets.sh
```

The script displays the version from `APP_VERSION` / `RELEASE_MANIFEST.json`,
requires confirmation, creates the GitHub Release if it does not exist, asks
before overwriting assets on an existing release, uploads the manifest-listed
files, and verifies that GitHub reports every expected asset.
