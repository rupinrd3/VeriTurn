#!/usr/bin/env bash
set -euo pipefail

ROOT="${VERITURN_HOME:-$HOME/.veriturn}"
MANIFEST="${1:-RELEASE_MANIFEST.json}"
ASSET_DIR="${2:-$(dirname "$MANIFEST")}"
STRICT="${VERITURN_VERIFY_STRICT:-0}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

read_manifest_field() {
  python3 - "$MANIFEST" "$1" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
value = manifest
for key in sys.argv[2].split("."):
    value = value.get(key, {}) if isinstance(value, dict) else {}
print(value if isinstance(value, str) else "")
PY
}

check_asset_hash() {
  local label="$1"
  local asset="$2"
  local expected="$3"
  if [[ -z "$asset" ]]; then
    echo "$label: no asset listed"
    return 0
  fi
  local path="$ASSET_DIR/$asset"
  if [[ ! -f "$path" ]]; then
    echo "$label: missing asset file $path"
    if [[ "$STRICT" == "1" ]]; then
      return 1
    fi
    return 0
  fi
  if [[ -z "$expected" || "$expected" == TO_BE_FILLED_* ]]; then
    echo "$label: present, hash not finalized in manifest"
    return 0
  fi
  local actual
  actual="$(sha256sum "$path" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "$label: SHA-256 mismatch for $path" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
  echo "$label: hash ok"
}

release_version="$(read_manifest_field release_version)"
asset_mode="$(read_manifest_field app.asset_mode)"
app_asset="$(read_manifest_field app.asset)"
app_sha="$(read_manifest_field app.sha256)"
runtime_cpu_asset="$(read_manifest_field runtime_tools.cpu.asset)"
runtime_cpu_sha="$(read_manifest_field runtime_tools.cpu.sha256)"
runtime_cuda_asset="$(read_manifest_field runtime_tools.cuda.asset)"
runtime_cuda_sha="$(read_manifest_field runtime_tools.cuda.sha256)"

echo "Release: ${release_version:-unknown}"
echo "App asset mode: ${asset_mode:-unknown}"
if [[ "$asset_mode" != "release_embedded_assets" ]]; then
  echo "Manifest does not declare release_embedded_assets." >&2
  exit 1
fi

check_asset_hash "app" "$app_asset" "$app_sha"
check_asset_hash "runtime_tools.cpu" "$runtime_cpu_asset" "$runtime_cpu_sha"
if [[ -n "$runtime_cuda_asset" ]]; then
  check_asset_hash "runtime_tools.cuda" "$runtime_cuda_asset" "$runtime_cuda_sha"
else
  echo "runtime_tools.cuda: no CUDA overlay asset in this release"
fi

echo "Install root: $ROOT"
for dir in "$ROOT/app" "$ROOT/runtime" "$ROOT/models"; do
  if [[ -d "$dir" ]]; then
    echo "$dir: present"
  else
    echo "$dir: missing"
  fi
done

if [[ -f "$ROOT/app/APP_VERSION" ]]; then
  installed_version="$(tr -d '[:space:]' < "$ROOT/app/APP_VERSION")"
  echo "installed app version: ${installed_version:-unknown}"
fi
if [[ -f "$ROOT/app/RUNTIME_VARIANT" ]]; then
  installed_variant="$(tr -d '[:space:]' < "$ROOT/app/RUNTIME_VARIANT")"
  echo "installed runtime variant: ${installed_variant:-unknown}"
fi
if [[ -f "$ROOT/app/INSTALLED_ASSETS.json" ]]; then
  echo "installed asset metadata: present"
fi
if [[ -f "$ROOT/runtime/RUNTIME_VERSION" ]]; then
  runtime_version="$(tr -d '[:space:]' < "$ROOT/runtime/RUNTIME_VERSION")"
  echo "installed runtime asset version: ${runtime_version:-unknown}"
fi
