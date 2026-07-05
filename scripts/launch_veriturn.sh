#!/usr/bin/env bash
set -euo pipefail

export VERITURN_HOME="${VERITURN_HOME:-$HOME/.veriturn}"
export VERITURN_RUNTIME_DIR="${VERITURN_RUNTIME_DIR:-$VERITURN_HOME/runtime}"
export VERITURN_MODEL_DIR="${VERITURN_MODEL_DIR:-$VERITURN_HOME/models}"
export LD_LIBRARY_PATH="$VERITURN_RUNTIME_DIR/lib:$VERITURN_RUNTIME_DIR/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

DEFAULT_VERITURN_HOME="$HOME/.veriturn"
if [[ "$VERITURN_HOME" != "$DEFAULT_VERITURN_HOME" ]]; then
  REAL_HOME="$HOME"
  HOME_SHIM="$VERITURN_HOME/.home-shim"
  mkdir -p "$HOME_SHIM"
  if [[ -e "$HOME_SHIM/.veriturn" && ! -L "$HOME_SHIM/.veriturn" ]]; then
    echo "Cannot launch with custom VERITURN_HOME because $HOME_SHIM/.veriturn exists and is not a symlink." >&2
    exit 1
  fi
  ln -sfn "$VERITURN_HOME" "$HOME_SHIM/.veriturn"
  export VERITURN_REAL_HOME="$REAL_HOME"
  export HOME="$HOME_SHIM"
fi

APP_BIN="${VERITURN_APP_BIN:-$VERITURN_HOME/app/bin/veriturn-studio}"
if [[ ! -x "$APP_BIN" ]]; then
  echo "VeriTurn app binary not found or not executable: $APP_BIN" >&2
  echo "Run scripts/setup_ubuntu.sh first." >&2
  exit 1
fi

exec "$APP_BIN" "$@"
