#!/usr/bin/env bash
set -euo pipefail

# Mode: release (default) or debug
BUILD_CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
    BUILD_CONFIG="debug"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

echo "=========================================="
echo "🚀 Building AIConsole for macOS (${BUILD_CONFIG})..."
echo "=========================================="

swift build -c "${BUILD_CONFIG}"

BIN_DIR="$(swift build --show-bin-path -c "${BUILD_CONFIG}")"
BIN_PATH="${BIN_DIR}/AIConsole"

DIST_DIR="${ROOT_DIR}/dist"
APP_NAME="AIConsole"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Clean dist
rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "📦 Assembling .app bundle..."
cp "${BIN_PATH}" "${MACOS_DIR}/AIConsole"
chmod +x "${MACOS_DIR}/AIConsole"

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
elif [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

cat << 'PLIST' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AIConsole</string>
    <key>CFBundleIdentifier</key>
    <string>com.personal.aiconsole</string>
    <key>CFBundleName</key>
    <string>AIConsole</string>
    <key>CFBundleDisplayName</key>
    <string>AIConsole</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh_CN</string>
        <string>zh-Hans</string>
        <string>zh</string>
    </array>
    <key>CFBundleAllowMixedLocalizations</key>
    <false/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

mkdir -p "${RESOURCES_DIR}/zh-Hans.lproj"
mkdir -p "${RESOURCES_DIR}/zh_CN.lproj"
touch "${RESOURCES_DIR}/zh-Hans.lproj/InfoPlist.strings"
touch "${RESOURCES_DIR}/zh_CN.lproj/InfoPlist.strings"

# Clear quarantine and sign with ad-hoc identity
echo "🔏 Signing application (ad-hoc)..."
xattr -cr "${APP_DIR}" || true
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true

echo "✅ App bundle created: ${APP_DIR}"

# Generate .zip distribution
echo "🗜️ Creating ZIP archive..."
ZIP_NAME="${APP_NAME}-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${DIST_DIR}/${ZIP_NAME}"
echo "✅ ZIP created: ${DIST_DIR}/${ZIP_NAME}"

# Generate .dmg installer
echo "💿 Creating DMG installer..."
DMG_TEMP="${DIST_DIR}/dmg_temp"
rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"

cp -R "${APP_DIR}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

DMG_NAME="${APP_NAME}-macOS.dmg"
DMG_OUTPUT="${DIST_DIR}/${DMG_NAME}"
rm -f "${DMG_OUTPUT}"

hdiutil create -volname "${APP_NAME}" \
               -srcfolder "${DMG_TEMP}" \
               -ov -format UDZO \
               "${DMG_OUTPUT}" > /dev/null

rm -rf "${DMG_TEMP}"
echo "✅ DMG created: ${DMG_OUTPUT}"

echo "=========================================="
echo "🎉 Build & packaging complete!"
echo "Artifacts in: ${DIST_DIR}"
ls -lh "${DIST_DIR}"
echo "=========================================="
