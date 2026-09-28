#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

# 签名证书名称不进仓库：写在 scripts/signing.local.env（已被 git 忽略），或直接设置环境变量。
#   AETHERSCREENS_SIGNING_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
if [ -f "$DIR/scripts/signing.local.env" ]; then
    source "$DIR/scripts/signing.local.env"
fi
SIGNING_IDENTITY="${AETHERSCREENS_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    echo "Error: set AETHERSCREENS_SIGNING_IDENTITY (or create scripts/signing.local.env)"
    exit 1
fi

echo "===> 0. Running all automated test scenarios (58+ tests)..."
swift test

echo "===> 1. Building release binary (arm64)..."
swift build -c release

RELEASE_BIN="$DIR/.build/arm64-apple-macosx/release/AetherScreensApp"
if [ ! -f "$RELEASE_BIN" ]; then
    echo "Error: Release binary not found at $RELEASE_BIN"
    exit 1
fi

echo "===> 2. Generating AppIcon.icns..."
mkdir -p AppIcon.iconset
sips -z 16 16     AppIcon_1024.png --out AppIcon.iconset/icon_16x16.png > /dev/null
sips -z 32 32     AppIcon_1024.png --out AppIcon.iconset/icon_16x16@2x.png > /dev/null
sips -z 32 32     AppIcon_1024.png --out AppIcon.iconset/icon_32x32.png > /dev/null
sips -z 64 64     AppIcon_1024.png --out AppIcon.iconset/icon_32x32@2x.png > /dev/null
sips -z 128 128   AppIcon_1024.png --out AppIcon.iconset/icon_128x128.png > /dev/null
sips -z 256 256   AppIcon_1024.png --out AppIcon.iconset/icon_128x128@2x.png > /dev/null
sips -z 256 256   AppIcon_1024.png --out AppIcon.iconset/icon_256x256.png > /dev/null
sips -z 512 512   AppIcon_1024.png --out AppIcon.iconset/icon_256x256@2x.png > /dev/null
sips -z 512 512   AppIcon_1024.png --out AppIcon.iconset/icon_512x512.png > /dev/null
sips -z 1024 1024 AppIcon_1024.png --out AppIcon.iconset/icon_512x512@2x.png > /dev/null
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset

echo "===> 3. Assembling AetherScreens.app bundle..."
APP_DIR="$DIR/build/release/AetherScreens.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$RELEASE_BIN" "$APP_DIR/Contents/MacOS/AetherScreens"
cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AetherScreens</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.aethernative.aetherscreens</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AetherScreens</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Aether Native. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>AetherScreens uses Bonjour to automatically discover nearby Macs with Screen Sharing enabled on your local network.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_rfb._tcp</string>
        <string>_apple-sas._tcp</string>
    </array>
</dict>
</plist>
EOF

cat << 'EOF' > "$APP_DIR/Contents/MacOS/AetherScreens.entitlements"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
EOF

echo "===> 4. Signing AetherScreens.app with Developer ID Application..."

codesign --force --options runtime --timestamp \
    --entitlements "$APP_DIR/Contents/MacOS/AetherScreens.entitlements" \
    --sign "$SIGNING_IDENTITY" \
    --deep "$APP_DIR"

echo "===> 5. Verifying code signature..."
codesign -vvv --deep --strict "$APP_DIR"

echo "===> 6. Packaging distributable Zip..."
cd "$DIR/build/release"
rm -f "AetherScreens-macOS-AppleSilicon-v1.0.0.zip"
zip -r -q "AetherScreens-macOS-AppleSilicon-v1.0.0.zip" "AetherScreens.app"

echo "===> 7. Installing to /Applications/AetherScreens.app..."
rm -rf /Applications/AetherScreens.app
cp -R "$APP_DIR" /Applications/AetherScreens.app
codesign -vvv --deep --strict /Applications/AetherScreens.app

echo "===> Formal Release Build, Testing, Signing & Installation Complete!"
echo "App Bundle: /Applications/AetherScreens.app"
echo "Distributable Zip: $DIR/build/release/AetherScreens-macOS-AppleSilicon-v1.0.0.zip"
