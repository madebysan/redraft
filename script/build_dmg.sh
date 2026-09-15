#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/Companion/Sources/Companion/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
SIGN_IDENTITY="Developer ID Application: Santiago Alonso Alexandre (QAMM2A6WRQ)"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool}"
RELEASE_DIR="$ROOT_DIR/Companion/.release"
DMG_NAME="Companion-$VERSION.dmg"
REPO_DMG="$RELEASE_DIR/$DMG_NAME"
DESKTOP_DMG="$HOME/Desktop/$DMG_NAME"
SHOULD_NOTARIZE=false

for arg in "$@"; do
  case "$arg" in
    --notarize|notarize) SHOULD_NOTARIZE=true ;;
    --help|-h) echo "usage: $0 [--notarize]"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ -e "$REPO_DMG" || -e "$DESKTOP_DMG" ]]; then
  echo "Refusing to overwrite an existing $DMG_NAME. Inspect the existing artifact first." >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"
BUILD_DIR="$(mktemp -d "$RELEASE_DIR/package-$VERSION.XXXXXX")"
APP_BUNDLE="$BUILD_DIR/Companion.app"
STAGING_DIR="$BUILD_DIR/dmg-contents"
APP_ZIP="$BUILD_DIR/Companion-$VERSION-notary.zip"

# Build/sign without stopping or replacing the installed app.
"$ROOT_DIR/script/build_and_run.sh" --build-only
ditto "$ROOT_DIR/dist/Companion.app" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

if [[ "$SHOULD_NOTARIZE" == true ]]; then
  ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  spctl --assess --type exec --verbose=4 "$APP_BUNDLE"
fi

mkdir -p "$STAGING_DIR"
ditto "$APP_BUNDLE" "$STAGING_DIR/Companion.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$ROOT_DIR/LICENSE" "$STAGING_DIR/LICENSE"
cp "$ROOT_DIR/resources/DMG-README.txt" "$STAGING_DIR/README.txt"
cp "$ROOT_DIR/Companion/Sources/Companion/Resources/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
if xcrun --find SetFile >/dev/null 2>&1; then
  xcrun SetFile -a C "$STAGING_DIR"
fi

hdiutil create -volname "Companion $VERSION" -srcfolder "$STAGING_DIR" -format UDZO "$REPO_DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$REPO_DMG"
if [[ "$SHOULD_NOTARIZE" == true ]]; then
  xcrun notarytool submit "$REPO_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$REPO_DMG"
  xcrun stapler validate "$REPO_DMG"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$REPO_DMG"
else
  echo "Signed only. Not notarized for distribution; run with --notarize for a release."
fi

codesign --verify --deep --strict "$APP_BUNDLE"
codesign --verify --verbose=2 "$REPO_DMG"
hdiutil verify "$REPO_DMG"
cp -n "$REPO_DMG" "$DESKTOP_DMG"
cmp "$REPO_DMG" "$DESKTOP_DMG"
(
  cd "$RELEASE_DIR"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)
echo "DMG: $REPO_DMG"
echo "Desktop copy: $DESKTOP_DMG"
echo "Checksums: $REPO_DMG.sha256"
echo "Packaged app: $APP_BUNDLE"
