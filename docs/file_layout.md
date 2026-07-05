# File Layout

All installed files live under a single install root, `~/.veriturn` by default
(override with the `VERITURN_HOME` environment variable before running any
`scripts/*.sh` command). Nothing is written outside this directory when the app
is launched through `scripts/launch_veriturn.sh`.

```text
~/.veriturn/
  app/                   replaceable app install + public metadata
    bin/veriturn-studio  the application binary
    data/                public manifests bundled with the app (language catalog,
                         voice manifest, recommended-models list, STT probe fixture)
    APP_VERSION          installed app version (vX.Y.Z)
    RUNTIME_VARIANT      "cpu" or "cuda" — which runtime bundle is installed
    INSTALLED_ASSETS.json app/runtime asset names, hashes, and installed variant
                         used by setup to skip only current binaries
    RELEASE_MANIFEST.json  copy of the manifest this install was verified against
  runtime/               replaceable runtime tool binaries + shared libraries
    RUNTIME_VERSION      release version marker embedded in the runtime asset
    bin/                 llama-server, whisper-server, piper, piper-tts-server,
                         sherpa-onnx-offline, sherpa-onnx-offline-tts,
                         veriturn-nemotron-stt, espeak-ng-data/
    lib/                 shared libraries (llama.cpp/whisper.cpp/onnxruntime/
                         sherpa-onnx/piper-phonemize, plus CUDA libraries when
                         the CUDA runtime overlay is installed)
  models/                user-installed and auto-downloaded model files
    stt/                 Whisper GGML, Nemotron ONNX, sherpa Indic Whisper
    tts/                 Piper voices, sherpa VITS/MMS voices, Kokoro (optional)
    llm/                 local LLM GGUF files (only if not using a cloud LLM)
    translation/         IndicTrans2/CT2 artifacts (only if offline translation
                         is enabled)
  db/                    local SQLite databases (sessions, evidence index, programs)
  evidence/              recordings, transcripts, exports, compliance reports
  backups/               timestamped database backups taken before each upgrade
  downloads/             per-version scratch space for downloaded release assets
                         (safe to delete; re-downloaded on the next install/upgrade)
  staging/               per-version scratch space used to unpack assets before
                         they are moved into app/ and runtime/ (safe to delete)
  logs/                  application log output
  .home-shim/            launcher-created compatibility shim for custom
                         VERITURN_HOME values; contains only a `.veriturn`
                         symlink back to this install root
  .env                   optional cloud provider API keys (mode 600, never
                         committed, read only by the app at startup)
```

## Custom install roots

Use `scripts/launch_veriturn.sh` for non-default `VERITURN_HOME` values. The
launcher exports `VERITURN_RUNTIME_DIR`, `VERITURN_MODEL_DIR`, and a loader path
covering both `runtime/lib` and `runtime/bin`. It also creates
`$VERITURN_HOME/.home-shim/.veriturn -> $VERITURN_HOME` before starting the app
so packaged builds that look up `$HOME/.veriturn/db/app.sqlite` still read and
write the database under the selected install root.

## Replaceable vs. preserved

Every `setup_ubuntu.sh` install or upgrade only replaces `app/` and
`runtime/` when their installed asset metadata does not match the checked-out
release manifest. Everything else — `models/`, `db/`, `evidence/`,
`backups/`, `downloads/`, `staging/`, `logs/`, and `.env` — is left
untouched. See `upgrade.md` for the exact swap and rollback mechanics.

## Uninstalling

`scripts/uninstall_veriturn.sh` removes only `app/` and `runtime/` by default.
Pass `--delete-user-data` to additionally remove `models/`, `db/`,
`evidence/`, `backups/`, and `.env` — this is destructive and cannot be
undone, so make sure you have exported or backed up any evidence you need
first.
