#!/usr/bin/env bash
set -euo pipefail

# Builds a double-clickable simple-git.app from a release build and ad-hoc signs
# it (enough for personal local use — not for distribution / App Store).
#
#   ./Assets/make_app.sh            # build into dist/simple-git.app
#   ./Assets/make_app.sh /Applications   # also install into the given dir
#
# Run Assets/generate_icon.sh first if the icon changed.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="simple-git"
BUNDLE_ID="com.wangxi.simple-git"
VERSION="1.0.0"
BUILD_NUM="1"

cd "$ROOT"

echo "==> swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP="$ROOT/dist/${APP_NAME}.app"
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Executable
cp "$BIN/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# SwiftPM resource bundle (Bundle.module: AppIcon/codex/claude/vscode pngs).
# Lives in Contents/Resources so Bundle.main.resourceURL finds it.
RES_BUNDLE="$(find "$BIN" -maxdepth 1 -name "${APP_NAME}_*.bundle" | head -1)"
cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"

# App icon
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUM}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP"

echo "built: $APP"

# Optional install
if [[ "${1:-}" != "" ]]; then
    DEST="$1/${APP_NAME}.app"
    echo "==> installing to $DEST"
    rm -rf "$DEST"
    cp -R "$APP" "$1/"
    echo "installed: $DEST"
fi
