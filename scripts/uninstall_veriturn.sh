#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Auto-detect custom VERITURN_HOME if a .shim file or directory exists in the release root
if [[ -z "${VERITURN_HOME:-}" && -e "$RELEASE_ROOT/.shim" ]]; then
  export VERITURN_HOME="$RELEASE_ROOT"
fi

ROOT="${VERITURN_HOME:-$HOME/.veriturn}"
DELETE_USER_DATA=0

if [[ "${1:-}" == "--delete-user-data" ]]; then
  DELETE_USER_DATA=1
fi

rm -rf "$ROOT/app" "$ROOT/runtime"

if [[ "$DELETE_USER_DATA" -eq 1 ]]; then
  rm -rf "$ROOT/models" "$ROOT/db" "$ROOT/evidence" "$ROOT/backups" "$ROOT/.env"
  echo "Removed app, runtime, and user data under $ROOT"
else
  echo "Removed app/runtime only. Preserved models, db, evidence, backups, and .env under $ROOT"
fi
