#!/usr/bin/env bash
set -euo pipefail

REPO="${VERITURN_RELEASE_REPO:-rupinrd3/VeriTurn}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
YES=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/upload_release_assets.sh [options]

Options:
  --yes          Do not prompt; useful for CI after the version is already checked.
  --repo OWNER/REPO
                 GitHub repository to upload to. Defaults to VERITURN_RELEASE_REPO
                 or rupinrd3/VeriTurn.
  --help        Show this help.

The script reads APP_VERSION / RELEASE_MANIFEST.json from this release repo,
verifies the local release assets, creates the GitHub Release if needed, uploads
the exact assets listed in the manifest, verifies that GitHub reports every
asset, and prints a summary.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      YES=1
      shift
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

need_cmd() {
  local cmd="$1"
  local guidance="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd is required. $guidance" >&2
    exit 1
  fi
}

confirm() {
  local prompt="$1"
  if [[ "$YES" -eq 1 ]]; then
    return 0
  fi
  local answer
  read -r -p "$prompt [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

manifest_path() {
  if [[ -f "$RELEASE_ROOT/RELEASE_MANIFEST.json" ]]; then
    printf '%s\n' "$RELEASE_ROOT/RELEASE_MANIFEST.json"
    return 0
  fi
  find "$RELEASE_ROOT" -maxdepth 1 -type f -name 'veriturn-release-manifest-*.json' | sort | tail -n 1
}

json_field() {
  python3 - "$MANIFEST" "$1" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in sys.argv[2].split("."):
    value = value.get(key, {}) if isinstance(value, dict) else {}
print(value if isinstance(value, str) else "")
PY
}

need_cmd gh "Install GitHub CLI, then run: gh auth login --hostname github.com"
need_cmd python3 "Install python3."
need_cmd sha256sum "Install coreutils."

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login --hostname github.com" >&2
  exit 1
fi

MANIFEST="$(manifest_path)"
if [[ -z "$MANIFEST" || ! -f "$MANIFEST" ]]; then
  echo "Release manifest not found in $RELEASE_ROOT. Run scripts/export_release_repo.sh from the development repo first." >&2
  exit 1
fi

VERSION=""
if [[ -f "$RELEASE_ROOT/APP_VERSION" ]]; then
  VERSION="$(tr -d '[:space:]' < "$RELEASE_ROOT/APP_VERSION")"
fi
MANIFEST_VERSION="$(json_field release_version)"
if [[ -z "$VERSION" ]]; then
  VERSION="$MANIFEST_VERSION"
fi
if [[ -z "$VERSION" || "$VERSION" != "$MANIFEST_VERSION" ]]; then
  echo "Version mismatch: APP_VERSION='${VERSION:-missing}', manifest release_version='${MANIFEST_VERSION:-missing}'." >&2
  exit 1
fi

APP_ASSET="$(json_field app.asset)"
RUNTIME_CPU_ASSET="$(json_field runtime_tools.cpu.asset)"
RUNTIME_CUDA_ASSET="$(json_field runtime_tools.cuda.asset)"
MANIFEST_ASSET="veriturn-release-manifest-${VERSION}.json"

assets=()
for asset in "$APP_ASSET" "$RUNTIME_CPU_ASSET" "$RUNTIME_CUDA_ASSET" "$MANIFEST_ASSET" "RELEASE_MANIFEST.json"; do
  if [[ -n "$asset" ]]; then
    assets+=("$asset")
  fi
done

echo "VeriTurn release asset upload"
echo "Repository: $REPO"
echo "Version: $VERSION"
echo "Release root: $RELEASE_ROOT"
echo
echo "Assets:"
for asset in "${assets[@]}"; do
  echo "  - $asset"
done
echo

if ! confirm "Proceed with upload for $VERSION?"; then
  echo "Aborted before upload."
  exit 1
fi

VERITURN_VERIFY_STRICT=1 "$SCRIPT_DIR/verify_release_assets.sh" "$MANIFEST" "$RELEASE_ROOT"

missing=0
for asset in "${assets[@]}"; do
  if [[ ! -f "$RELEASE_ROOT/$asset" ]]; then
    echo "Missing local upload asset: $RELEASE_ROOT/$asset" >&2
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

release_exists=0
if gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  release_exists=1
fi

upload_args=()
if [[ "$release_exists" -eq 1 ]]; then
  echo "GitHub Release $VERSION already exists in $REPO."
  if ! confirm "Overwrite existing assets with the local files listed above?"; then
    echo "Aborted; no assets uploaded."
    exit 1
  fi
  upload_args+=(--clobber)
else
  echo "GitHub Release $VERSION does not exist; creating it."
  gh release create "$VERSION" --repo "$REPO" --title "VeriTurn Studio $VERSION" --notes-file "$RELEASE_ROOT/RELEASE_NOTES.md"
fi

file_args=()
for asset in "${assets[@]}"; do
  file_args+=("$RELEASE_ROOT/$asset")
done

gh release upload "$VERSION" "${file_args[@]}" --repo "$REPO" "${upload_args[@]}"

uploaded_json="$(mktemp)"
gh release view "$VERSION" --repo "$REPO" --json assets > "$uploaded_json"
python3 - "$uploaded_json" "${assets[@]}" <<'PY'
import json
import pathlib
import sys

doc = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
uploaded = {asset.get("name", "") for asset in doc.get("assets", [])}
expected = set(sys.argv[2:])
missing = sorted(expected - uploaded)
if missing:
    print("GitHub upload verification failed; missing assets:", file=sys.stderr)
    for name in missing:
        print(f"  - {name}", file=sys.stderr)
    raise SystemExit(1)

print("Uploaded assets verified on GitHub:")
for name in sorted(expected):
    print(f"  - {name}")
PY
rm -f "$uploaded_json"

echo "Publishing the release (moving from Draft to Published)..."
gh release edit "$VERSION" --draft=false --repo "$REPO"

echo
echo "Upload and publish complete."
echo "Release: $VERSION"
echo "Repository: $REPO"

