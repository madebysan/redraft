#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Companion"
LEGACY_APP_NAME="CompanionV2"
PRODUCT_NAME="Companion"
BUNDLE_ID="com.santiagoalonso.companion"
SIGN_IDENTITY="Developer ID Application: Santiago Alonso Alexandre (QAMM2A6WRQ)"
SWIFT_BUILD_FLAGS=(-c release --arch arm64 --arch x86_64)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/Companion"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALLED_APP_BUNDLE="/Applications/$APP_NAME.app"
LEGACY_INSTALLED_APP_BUNDLE="/Applications/$LEGACY_APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_BINARY="$MACOS_DIR/$APP_NAME"
INSTALLED_APP_BINARY="$INSTALLED_APP_BUNDLE/Contents/MacOS/$APP_NAME"
INFO_PLIST="$PACKAGE_DIR/Sources/Companion/Resources/Info.plist"
ICON_FILE="$PACKAGE_DIR/Sources/Companion/Resources/AppIcon.icns"

# Isolated visual QA: no installed app replacement, signing identity, or live defaults.
if [[ "$MODE" == "--preview" ]]; then
  shift
  PREVIEW_BUNDLE="$DIST_DIR/CompanionPreview.app"
  swift build --package-path "$PACKAGE_DIR"
  PREVIEW_BINARY="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/$PRODUCT_NAME"
  mkdir -p "$PREVIEW_BUNDLE/Contents/MacOS" "$PREVIEW_BUNDLE/Contents/Resources"
  cp "$PREVIEW_BINARY" "$PREVIEW_BUNDLE/Contents/MacOS/$APP_NAME"
  mkdir -p "$PREVIEW_BUNDLE/Contents/Frameworks"
  /usr/bin/ditto "$(dirname "$PREVIEW_BINARY")/Sparkle.framework" "$PREVIEW_BUNDLE/Contents/Frameworks/Sparkle.framework"
  cp "$INFO_PLIST" "$PREVIEW_BUNDLE/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.santiagoalonso.companion.preview' "$PREVIEW_BUNDLE/Contents/Info.plist"
  codesign --force --sign - "$PREVIEW_BUNDLE"
  /usr/bin/open -n "$PREVIEW_BUNDLE" --args --palette-preview "$@"
  exit 0
fi

cd "$PACKAGE_DIR"
swift build "${SWIFT_BUILD_FLAGS[@]}"
BUILD_BINARY="$(swift build "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)/$PRODUCT_NAME"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
fi
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/"
# Embed Sparkle, the in-app updater. ditto keeps the framework's symlinks intact.
mkdir -p "$CONTENTS_DIR/Frameworks"
/usr/bin/ditto "$(dirname "$BUILD_BINARY")/Sparkle.framework" "$CONTENTS_DIR/Frameworks/Sparkle.framework"

sign_app() {
  if security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
    # Sparkle's nested code inside-out first, then the app, without --deep.
    local fw="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    codesign -f -o runtime --timestamp -s "$SIGN_IDENTITY" "$fw/Versions/B/XPCServices/Installer.xpc"
    codesign -f -o runtime --timestamp --preserve-metadata=entitlements -s "$SIGN_IDENTITY" "$fw/Versions/B/XPCServices/Downloader.xpc"
    codesign -f -o runtime --timestamp -s "$SIGN_IDENTITY" "$fw/Versions/B/Autoupdate"
    codesign -f -o runtime --timestamp -s "$SIGN_IDENTITY" "$fw/Versions/B/Updater.app"
    codesign -f -o runtime --timestamp -s "$SIGN_IDENTITY" "$fw"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  else
    echo "Developer ID signing identity unavailable; installed app was not changed." >&2
    exit 1
  fi
}

replace_installed_app() {
  if [[ -d "$INSTALLED_APP_BUNDLE" ]]; then
    BACKUP_DIR="$(mktemp -d "$ROOT_DIR/work/installed-backup.XXXXXX")"
    /usr/bin/ditto "$INSTALLED_APP_BUNDLE" "$BACKUP_DIR/$APP_NAME.app"
    echo "Updating in place; macOS may ask you to re-grant Accessibility or Input Monitoring."
    echo "Previous app preserved at $BACKUP_DIR/$APP_NAME.app"
  fi
  /usr/bin/ditto "$APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
  /usr/bin/xattr -dr com.apple.quarantine "$INSTALLED_APP_BUNDLE" >/dev/null 2>&1 || true
}

install_app() {
  sign_app
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  mkdir -p "$ROOT_DIR/work"
  replace_installed_app
  codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP_BUNDLE" >/dev/null
}

open_app() {
  install_app
  /usr/bin/open -n "$INSTALLED_APP_BUNDLE"
}

case "$MODE" in
  --build-only)
    sign_app
    codesign --verify --deep --strict "$APP_BUNDLE"
    echo "Signed app built at $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --install|install)
    install_app
    /usr/bin/open -n "$INSTALLED_APP_BUNDLE"
    ;;
  --debug|debug)
    install_app
    lldb -- "$INSTALLED_APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running from $INSTALLED_APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--build-only|--preview|--install|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
