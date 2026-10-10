#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:?Release output required}"
VERSION="${2:?Version required}"
PROFILE="${3:?Keychain notary profile required}"
DMG="$OUTPUT/AetherScreens-macOS-AppleSilicon-v$VERSION.dmg"
ZIP="$OUTPUT/AetherScreens-macOS-AppleSilicon-v$VERSION.zip"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --timeout 10m --output-format json > "$OUTPUT/notarization-dmg-$VERSION.json"
python3 - "$OUTPUT/notarization-dmg-$VERSION.json" <<'PY'
import json, sys
with open(sys.argv[1]) as source:
    result = json.load(source)
if result.get('status') != 'Accepted':
    raise SystemExit('DMG notarization failed: ' + str(result.get('status')))
PY
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
(cd "$OUTPUT" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")") > "$OUTPUT/SHA256SUMS.txt"
"$DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update" --account com.aethernative.aetherscreens "$DMG" > "$OUTPUT/sparkle-signature.txt"
echo "Final notarized and update-signed archive ready: $DMG"
