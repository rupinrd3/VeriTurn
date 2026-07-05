# Upgrade

## How to upgrade

```bash
git pull
scripts/setup_ubuntu.sh
```

The installer reads the checked-out `APP_VERSION` / `RELEASE_MANIFEST.json`
and downloads the exact app/runtime assets for that release. `--version
vX.Y.Z` and `--upgrade vX.Y.Z` remain supported aliases when you need to pin
a specific release tag.

## What is preserved vs. replaced

Only `~/.veriturn/app` and `~/.veriturn/runtime` are replaced. Everything
else is untouched: `models/`, `db/`, `evidence/`, `backups/`, and `.env`.
See `file_layout.md` for the full directory map.

## What happens, step by step

1. The installer resolves the target version from this git-pulled release
   repository, or from `--version` if one is provided.
2. It compares that target version against `~/.veriturn/app/APP_VERSION` and
   compares the installed app/runtime asset metadata in
   `~/.veriturn/app/INSTALLED_ASSETS.json` against the target
   `RELEASE_MANIFEST.json`.
3. If the requested version is **older** than the installed one, the
   installer refuses and exits — see "Downgrade is not supported" below.
4. If the requested version is the **same** and the installed app/runtime
   asset hashes plus CPU/CUDA variant are current, the installer skips the
   binary reinstall and runs verification/model checks.
5. If the requested version is the **same** but installed binaries are
   missing, stale, or built for a different runtime variant, the installer
   downloads and reinstalls the exact release assets.
6. Before touching anything installed, it takes a timestamped backup of the
   entire `db/` directory into `backups/db-<timestamp>/`.
7. The new app/runtime are staged and validated (binary present + executable,
   `ldd` sanity check) before anything currently installed is touched.
8. The currently installed `app/`/`runtime/` are moved aside to
   `app.prev`/`runtime.prev`, then the new staged versions are moved into
   place. This is a same-filesystem `mv`, not a copy, so the swap is fast and
   avoids a half-written app directory if the process is interrupted midway
   through staging.
9. `scripts/verify_release_assets.sh` re-checks the freshly installed files'
   SHA-256 against the manifest.

## Downgrade is not supported

Once an upgraded app has applied its (forward-only) database migrations,
those migrations cannot be reversed by reinstalling an older app version —
the older app does not know how to read the newer schema. The installer
detects this and refuses:

```text
Refusing downgrade from <installed> to <requested>. Restore a DB backup manually before downgrading.
```

To intentionally go back to an older version, restore a matching database
backup from `~/.veriturn/backups/db-<timestamp>/` first (replacing the
current `db/` contents with that backup), then run the installer for the
older version.

## Manual rollback of app/runtime only (no DB change)

If you upgraded and want to revert just the binaries (not the database) and
did not yet run another install afterward, `app.prev`/`runtime.prev` still
hold the previous version's files under `~/.veriturn`. Swap them back
manually:

```bash
mv ~/.veriturn/app ~/.veriturn/app.rejected
mv ~/.veriturn/runtime ~/.veriturn/runtime.rejected
mv ~/.veriturn/app.prev ~/.veriturn/app
mv ~/.veriturn/runtime.prev ~/.veriturn/runtime
```

Only do this if the database has not since been migrated by the newer app
(i.e. you have not launched the newer version and let it run its startup
migrations) — otherwise use the DB-backup restore path above instead.

## Verifying without upgrading

```bash
scripts/setup_ubuntu.sh --verify
```

Re-checks the currently installed files' SHA-256 values against
`RELEASE_MANIFEST.json` without downloading or changing anything — useful
after a suspected disk issue or partial install.
