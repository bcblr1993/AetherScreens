#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"
if [ -f "$DIR/scripts/signing.local.env" ]; then
    source "$DIR/scripts/signing.local.env"
fi
VERSION="${AETHERSCREENS_VERSION:-1.0.0}"
BUILD_NUMBER="${AETHERSCREENS_BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${AETHERSCREENS_SIGNING_IDENTITY:?Set AETHERSCREENS_SIGNING_IDENTITY or scripts/signing.local.env}"
NOTARY_PROFILE="${AETHERSCREENS_NOTARY_PROFILE:?Set AETHERSCREENS_NOTARY_PROFILE to a Keychain notarytool profile}"
OUTPUT="$DIR/build/release"
mkdir -p "$OUTPUT"
STAGE="$(mktemp -d "$OUTPUT/staging.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

swift test
swift build -c release --arch arm64
RELEASE_BIN="$(swift build -c release --arch arm64 --show-bin-path)/AetherScreensApp"
APP_DIR="$STAGE/AetherScreens.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$RELEASE_BIN" "$APP_DIR/Contents/MacOS/AetherScreens"
cp assets/branding/AppIcon-v1.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
cp assets/licenses/BigInt-MIT.txt "$APP_DIR/Contents/Resources/BigInt-MIT.txt"
ditto "$(dirname "$RELEASE_BIN")/AetherScreens_AetherScreensCore.bundle" "$APP_DIR/Contents/Resources/AetherScreens_AetherScreensCore.bundle"
cp -R assets/localization/*.lproj "$APP_DIR/Contents/Resources/"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>CFBundleExecutable</key><string>AetherScreens</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>com.aethernative.aetherscreens</string>
<key>CFBundleName</key><string>AetherScreens</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Aether Native.</string>
<key>NSLocalNetworkUsageDescription</key><string>Discover nearby Macs with Screen Sharing enabled.</string>
<key>NSBonjourServices</key><array><string>_rfb._tcp</string><string>_apple-sas._tcp</string></array>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
NOTARY_ZIP="$STAGE/notarization.zip"
ditto -c -k --keepParent "$APP_DIR" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 10m --output-format json > "$OUTPUT/notarization-$VERSION.json"
python3 - "$OUTPUT/notarization-$VERSION.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization failed: ' + str(result.get('status')))
PY
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl --assess --type execute --verbose "$APP_DIR"
ZIP="$OUTPUT/AetherScreens-macOS-AppleSilicon-v$VERSION.zip"
DMG="$OUTPUT/AetherScreens-macOS-AppleSilicon-v$VERSION.dmg"
ditto -c -k --keepParent "$APP_DIR" "$ZIP"
ln -s /Applications "$STAGE/Applications"
rm "$NOTARY_ZIP"
hdiutil create -volname "AetherScreens $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
ditto "$APP_DIR" "$OUTPUT/AetherScreens.app"
(cd "$OUTPUT" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")") > "$OUTPUT/SHA256SUMS.txt"
echo "Signed and notarized release ready: $OUTPUT"
