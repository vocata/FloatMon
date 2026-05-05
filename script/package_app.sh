#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FloatMon"
BUNDLE_ID="local.floatmon"
BUNDLE_DISPLAY_NAME="FloatMon"
MINIMUM_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist.noindex"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
EXECUTABLE="$ROOT_DIR/.build/debug/$APP_NAME"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"

SWIFTPM_CACHE_DIR="$ROOT_DIR/.build/swiftpm-cache"
SWIFTPM_CONFIG_DIR="$ROOT_DIR/.build/swiftpm-config"
SWIFTPM_SECURITY_DIR="$ROOT_DIR/.build/swiftpm-security"
CLANG_CACHE_DIR="$ROOT_DIR/.build/module-cache"

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

build_executable() {
  export CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR"
  mkdir -p "$CLANG_CACHE_DIR" "$SWIFTPM_CACHE_DIR" "$SWIFTPM_CONFIG_DIR" "$SWIFTPM_SECURITY_DIR"

  swift build \
    --disable-sandbox \
    --manifest-cache local \
    --cache-path "$SWIFTPM_CACHE_DIR" \
    --config-path "$SWIFTPM_CONFIG_DIR" \
    --security-path "$SWIFTPM_SECURITY_DIR"
}

create_bundle_layout() {
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

  cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
}

write_info_plist() {
  cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$BUNDLE_DISPLAY_NAME</string>
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
  <string>$MINIMUM_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

sign_bundle() {
  local signing_identity="${CODE_SIGN_IDENTITY:-}"
  if [[ -z "$signing_identity" ]]; then
    signing_identity="$(detect_signing_identity)"
  fi

  if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
    echo "warning: no stable code signing identity found; using ad-hoc signing." >&2
    echo "warning: macOS Accessibility permission may need to be granted again after each rebuild." >&2
  fi

  /usr/bin/codesign --force --deep --sign "$signing_identity" "$APP_BUNDLE" >/dev/null
}

main() {
  cd "$ROOT_DIR"
  build_executable
  create_bundle_layout
  write_info_plist
  sign_bundle
  echo "$APP_BUNDLE"
}

main "$@"
