#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DynamicIslandMac"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist.noindex/$APP_NAME.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "$APP_BUNDLE does not exist. Run make run first." >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
/usr/bin/open -n "$APP_BUNDLE"

case "${1:-}" in
  --verify)
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running"
    ;;
esac
