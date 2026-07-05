#!/usr/bin/env bash
set -euo pipefail

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
