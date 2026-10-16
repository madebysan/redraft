#!/usr/bin/env bash
# Builds the sandboxed Mac App Store edition of Redraft.
#
#   script/build_app_store.sh --local   Signed with Developer ID, for trying it on this Mac.
#   script/build_app_store.sh           Signed for the App Store: needs REDRAFT_MAS_PROFILE (a Mac App Store
#                                       provisioning profile for $BUNDLE_ID) and a Mac installer certificate.
#                                       Produces Companion/.release/appstore/Redraft-<version>.pkg for upload.
set -euo pipefail

MODE="${1:-store}"
if [[ -n "${REDRAFT_MAS_PROFILE:-}" ]]; then REDRAFT_MAS_PROFILE="$(realpath "$REDRAFT_MAS_PROFILE")"; fi
TEAM_ID="QAMM2A6WRQ"
BUNDLE_ID="${REDRAFT_MAS_BUNDLE_ID:-com.santiagoalonso.redraft}"
APP_SIGN_IDENTITY="Apple Distribution: Santiago Alonso Alexandre ($TEAM_ID)"
LOCAL_SIGN_IDENTITY="Developer ID Application: Santiago Alonso Alexandre ($TEAM_ID)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/Companion"
INFO_PLIST="$PACKAGE_DIR/Sources/Companion/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
OUT_DIR="$PACKAGE_DIR/.release/appstore"
APP_BUNDLE="$OUT_DIR/Redraft.app"
CONTENTS="$APP_BUNDLE/Contents"
ENTITLEMENTS="$OUT_DIR/Redraft.entitlements"
SCRATCH="$PACKAGE_DIR/.build-appstore"
BUILD_FLAGS=(-c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH" --manifest-cache none)

# The store manifest drops Sparkle, and SwiftPM would rewrite Package.resolved without it.
RESOLVED="$PACKAGE_DIR/Package.resolved"
RESOLVED_BACKUP="$(mktemp)"
cp "$RESOLVED" "$RESOLVED_BACKUP"
trap 'cp "$RESOLVED_BACKUP" "$RESOLVED"; /bin/rm -f "$RESOLVED_BACKUP"' EXIT

cd "$PACKAGE_DIR"
REDRAFT_APP_STORE=1 swift build "${BUILD_FLAGS[@]}"
BINARY="$(REDRAFT_APP_STORE=1 swift build "${BUILD_FLAGS[@]}" --show-bin-path)/Companion"
if otool -L "$BINARY" | grep -qi sparkle; then echo "Sparkle is linked; refusing to package." >&2; exit 1; fi
if nm -u "$BINARY" | grep -q '_AXUIElement\|_AXIsProcessTrusted'; then echo "Accessibility API is linked; refusing to package." >&2; exit 1; fi

mkdir -p "$OUT_DIR"
if [[ -d "$APP_BUNDLE" ]]; then /usr/bin/trash "$APP_BUNDLE"; fi
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/Redraft"
cp "$PACKAGE_DIR/Sources/Companion/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/"

PLIST="$CONTENTS/Info.plist"
cp "$INFO_PLIST" "$PLIST"
for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks; do
  /usr/libexec/PlistBuddy -c "Delete :$key" "$PLIST"
done
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.productivity" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$PLIST"

cat > "$ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
$(if [[ "$MODE" != "--local" ]]; then cat <<IDS
	<key>com.apple.application-identifier</key>
	<string>$TEAM_ID.$BUNDLE_ID</string>
	<key>com.apple.developer.team-identifier</key>
	<string>$TEAM_ID</string>
IDS
fi)
</dict>
</plist>
PLIST

if [[ "$MODE" == "--local" ]]; then
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$LOCAL_SIGN_IDENTITY" "$APP_BUNDLE"
  codesign --verify --strict --verbose=2 "$APP_BUNDLE"
  echo "Local store build: $APP_BUNDLE (bundle ID $BUNDLE_ID). Quit the DMG version first; both use ⌘⇧E."
  exit 0
fi

: "${REDRAFT_MAS_PROFILE:?Set REDRAFT_MAS_PROFILE to the Mac App Store provisioning profile for $BUNDLE_ID}"
cp "$REDRAFT_MAS_PROFILE" "$CONTENTS/embedded.provisionprofile"
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$APP_SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

INSTALLER_IDENTITY="$(security find-identity -v | grep -E '(3rd Party Mac Developer Installer|Mac Installer Distribution).*\('"$TEAM_ID"'\)' | head -1 | sed -E 's/^.*"(.*)"$/\1/')"
if [[ -z "$INSTALLER_IDENTITY" ]]; then echo "No Mac installer certificate for team $TEAM_ID in the keychain." >&2; exit 1; fi
PKG="$OUT_DIR/Redraft-$VERSION.pkg"
if [[ -e "$PKG" ]]; then /usr/bin/trash "$PKG"; fi
productbuild --component "$APP_BUNDLE" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
pkgutil --check-signature "$PKG"
echo "App Store package: $PKG"
