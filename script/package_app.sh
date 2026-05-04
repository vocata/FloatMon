#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DynamicIslandMac"
BUNDLE_ID="local.dynamic-island-mac"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
EXECUTABLE="$ROOT_DIR/.build/debug/$APP_NAME"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"

detect_signing_identity() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F '"' '
    /"Developer ID Application:/ { print $2; found = 1; exit }
    /"Apple Distribution:/ { print $2; found = 1; exit }
    /"Apple Development:/ && !candidate { candidate = $2 }
    /"Mac Developer:/ && !candidate { candidate = $2 }
    END {
      if (!found && candidate) {
        print candidate
      }
    }
  '
}

cd "$ROOT_DIR"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$ROOT_DIR/.build/swiftpm-cache" "$ROOT_DIR/.build/swiftpm-config" "$ROOT_DIR/.build/swiftpm-security"

swift build \
  --disable-sandbox \
  --manifest-cache local \
  --cache-path "$ROOT_DIR/.build/swiftpm-cache" \
  --config-path "$ROOT_DIR/.build/swiftpm-config" \
  --security-path "$ROOT_DIR/.build/swiftpm-security"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>Dynamic Island Mac</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(detect_signing_identity)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  echo "warning: no stable code signing identity found; using ad-hoc signing." >&2
  echo "warning: macOS Accessibility permission may need to be granted again after each rebuild." >&2
fi

/usr/bin/codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE" >/dev/null
echo "$APP_BUNDLE"
