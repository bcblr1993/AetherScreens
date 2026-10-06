#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"
# Inspection builds stop before loading any signing configuration.
if [ "${1:-}" = "--compile-only" ]; then
    shift
    exec /usr/bin/python3 "$DIR/scripts/build_macos_app.py" "$@"
fi
if [ "$#" -ne 0 ]; then
    echo "Usage: package_release.sh [--compile-only build-options]" >&2
    exit 2
fi
if [ -f "$DIR/scripts/signing.local.env" ]; then
    source "$DIR/scripts/signing.local.env"
fi
VERSION="${AETHERSCREENS_VERSION:-1.0.0}"
BUILD_NUMBER="${AETHERSCREENS_BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${AETHERSCREENS_SIGNING_IDENTITY:?Set AETHERSCREENS_SIGNING_IDENTITY or scripts/signing.local.env}"
NOTARY_PROFILE="${AETHERSCREENS_NOTARY_PROFILE:?Set AETHERSCREENS_NOTARY_PROFILE to a Keychain notarytool profile}"
HOST_PROFILE="${AETHERSCREENS_MAC_HOST_PROFILE:?Set a provisioning profile authorizing the host production App Group}"
WIDGET_PROFILE="${AETHERSCREENS_MAC_WIDGET_PROFILE:?Set a provisioning profile authorizing the Widget production App Group}"
OUTPUT="$DIR/build/release"
mkdir -p "$OUTPUT"
STAGE="$(mktemp -d "$OUTPUT/staging.XXXXXX")"
NATIVE_PARENT="$(mktemp -d "$OUTPUT/native.XXXXXX")"
trap 'rm -rf "$STAGE" "$NATIVE_PARENT"' EXIT

swift test
NATIVE_BUILD="$NATIVE_PARENT/build"
/usr/bin/python3 "$DIR/scripts/build_macos_app.py" --build-root "$NATIVE_BUILD" --version "$VERSION" --build-number "$BUILD_NUMBER"
APP_DIR="$STAGE/AetherScreens.app"
ditto "$NATIVE_BUILD/DerivedData/Build/Products/Release/AetherScreens.app" "$APP_DIR"
WIDGET_DIR="$APP_DIR/Contents/PlugIns/AetherScreensWidgets.appex"
cp "$HOST_PROFILE" "$APP_DIR/Contents/embedded.provisionprofile"
cp "$WIDGET_PROFILE" "$WIDGET_DIR/Contents/embedded.provisionprofile"
# Sign the native runtime libraries before their extension/host containers.
for CONTAINER in "$APP_DIR" "$WIDGET_DIR"; do
    if [ -d "$CONTAINER/Contents/Frameworks" ]; then
        for OBJECT in "$CONTAINER/Contents/Frameworks/"*; do
            [ -e "$OBJECT" ] || continue
            case "$OBJECT" in
                *.framework|*.dylib)
                    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$OBJECT"
                    ;;
                *)
                    echo "Unsupported nested runtime object in release bundle" >&2
                    exit 2
                    ;;
            esac
        done
    fi
done
codesign --force --options runtime --timestamp --entitlements "$DIR/assets/AetherScreensMacReleaseWidgets.entitlements" --sign "$SIGNING_IDENTITY" "$WIDGET_DIR"
codesign --force --options runtime --timestamp --entitlements "$DIR/assets/AetherScreensMacReleaseHost.entitlements" --sign "$SIGNING_IDENTITY" "$APP_DIR"
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
