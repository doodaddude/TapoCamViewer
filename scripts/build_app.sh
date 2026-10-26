#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "Building TapoCamViewer release binary..."
swift build -c release

APP_NAME="TapoCamViewer.app"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp .build/release/TapoCamViewer "${MACOS}/TapoCamViewer"
cp bin/go2rtc "${MACOS}/go2rtc"
cp bin/go2rtc "${RESOURCES}/go2rtc"
cp Sources/TapoCamViewer/Services/TapoRecordingBridge.py "${RESOURCES}/TapoRecordingBridge.py"

if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "${RESOURCES}/AppIcon.icns"
fi

cat << 'PLIST' > "${CONTENTS}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TapoCamViewer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.tapo.camviewer</string>
    <key>CFBundleName</key>
    <string>TapoCamViewer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# Sign application bundle if signing identity is available
IDENTITY="Developer ID Application: Dakota Hilchey (2FCUC227QF)"
ENTITLEMENTS="entitlements.plist"

if security find-identity -p codesigning -v | grep -q "$IDENTITY"; then
    echo "Signing with Developer ID: $IDENTITY"
    codesign --force --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "${MACOS}/go2rtc"
    codesign --force --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "${RESOURCES}/go2rtc"
    codesign --force --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "${MACOS}/TapoCamViewer"
    codesign --force --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "${APP_DIR}"
    codesign --verify --deep --strict --verbose=2 "${APP_DIR}"
else
    echo "Developer ID not found; skipping codesign."
fi

echo "Built and signed ${APP_DIR} successfully!"
