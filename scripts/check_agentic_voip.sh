#!/usr/bin/env bash
# Read-only Agentic VOIP readiness diagnostic for a packaged VeriTurn install.
# Never contacts Twilio/Plivo, never starts a tunnel, never dials.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${VERITURN_HOME:-$HOME/.veriturn}"
ENV_FILE="$ROOT/.env"
fail=0

check() { local name="$1" remedy="$2"; shift 2; if "$@"; then printf '[ready] %s\n' "$name"; else printf '[blocked] %s — %s\n' "$name" "$remedy"; fail=1; fi; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }
has_env() { [[ -n "${!1:-}" ]] || { [[ -f "$ENV_FILE" ]] && grep -qE "^${1}=.+" "$ENV_FILE"; }; }
port_free() { ! (command -v ss >/dev/null && ss -ltn 2>/dev/null | grep -qE ":$1\\b"); }

RUNNER_LAUNCHER="$ROOT/runtime/voice-runner/linux-x64/run-voice-runner.sh"
check "bundled voice-runner launcher" "reinstall/repair: $RELEASE_ROOT/scripts/setup_ubuntu.sh" test -x "$RUNNER_LAUNCHER"
check "cloudflared executable" "install cloudflared (see setup_ubuntu.sh Agentic VOIP guidance); do not expose loopback ports" has_cmd cloudflared
check "control port 8092 available" "stop the conflicting local process" port_free 8092
check "decision port 8090 available" "stop the conflicting local process" port_free 8090
check "telemetry port 8091 available" "stop the conflicting local process" port_free 8091

SPOOL_ROOT="${VERITURN_SPOOL_ROOT:-$ROOT/agentic_spool}"
mkdir -p "$SPOOL_ROOT" 2>/dev/null || true
check "spool root writable" "create a writable $SPOOL_ROOT or configure Settings > Agentic VOIP spool root" test -w "$SPOOL_ROOT"

for provider in twilio plivo; do
  if [[ "$provider" == twilio ]]; then keys=(TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER); else keys=(PLIVO_AUTH_ID PLIVO_AUTH_TOKEN PLIVO_FROM_NUMBER); fi
  missing=0; for key in "${keys[@]}"; do has_env "$key" || missing=1; done
  [[ $missing -eq 0 ]] && printf '[ready] %s credentials present (values redacted)\n' "$provider" || printf '[manual] %s credentials missing in %s; that provider cannot be armed\n' "$provider" "$ENV_FILE"
done

printf 'No provider, tunnel, or phone was contacted.\n'
printf 'Default tunnel mode is Quick (free *.trycloudflare.com): no VERITURN_PUBLIC_BASE_URL required.\n'
printf 'After each app launch: Setup Checks → Start runner → Start free Quick Tunnel, then arm.\n'
printf 'Live dials also require VERITURN_CPAAS_LIVE=1 and an approved test number.\n'
exit "$fail"
