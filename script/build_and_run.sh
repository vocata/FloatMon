#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DynamicIslandMac"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist.noindex/$APP_NAME.app"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

"$ROOT_DIR/script/package_app.sh" >/dev/null

/usr/bin/open -n "$APP_BUNDLE"

case "${1:-}" in
  --verify)
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running"
    ;;
  --logs)
    /usr/bin/log stream --style compact --predicate "process == '$APP_NAME'"
    ;;
esac
