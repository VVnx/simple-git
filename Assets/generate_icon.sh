#!/usr/bin/env bash
set -euo pipefail

# Builds every app-icon artifact from the single source of truth, icon.svg:
#   - app-icon-1024.png        master / App Store marketing image
#   - AppIcon.icns             for `swift run` bundles or manual packaging
#   - AppIcon.appiconset/      Asset Catalog for Xcode / App Store submission
#
# Prefers rsvg-convert (sharp at every size); falls back to qlmanage + sips.

ROOT="$(cd "$(dirname "$0")" && pwd)"
SVG="$ROOT/icon.svg"
MASTER="$ROOT/app-icon-1024.png"
ICONSET="$ROOT/AppIcon.iconset"
APPICONSET="$ROOT/AppIcon.appiconset"

# Render the SVG to a square PNG of the given pixel size.
render() {
    local size="$1" out="$2"
    if command -v rsvg-convert >/dev/null 2>&1; then
        rsvg-convert -w "$size" -h "$size" "$SVG" -o "$out"
    else
        # Fallback: render a master via Quick Look once, then downscale.
        if [[ ! -f "$MASTER" ]]; then
            qlmanage -t -s 1024 -o "$ROOT" "$SVG" >/dev/null 2>&1
            mv "$ROOT/icon.svg.png" "$MASTER"
        fi
        sips -z "$size" "$size" "$MASTER" --out "$out" >/dev/null
    fi
}

# 1024 master (App Store marketing image)
render 1024 "$MASTER"

# Dock icon for `swift run` (bundled as a SwiftPM resource, set at launch).
render 1024 "$ROOT/../Sources/SimpleGit/Resources/AppIcon.png"

# .iconset -> .icns
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for base in 16 32 128 256 512; do
    render "$base"          "$ICONSET/icon_${base}x${base}.png"
    render "$((base * 2))"  "$ICONSET/icon_${base}x${base}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$ROOT/AppIcon.icns"
rm -rf "$ICONSET"

# Asset Catalog (Xcode / App Store)
rm -rf "$APPICONSET"; mkdir -p "$APPICONSET"
for base in 16 32 128 256 512; do
    render "$base"          "$APPICONSET/icon_${base}x${base}.png"
    render "$((base * 2))"  "$APPICONSET/icon_${base}x${base}@2x.png"
done
cat > "$APPICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16",   "scale" : "1x", "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "size" : "16x16",   "scale" : "2x", "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "1x", "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "2x", "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "1x", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "2x", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "1x", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "2x", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "1x", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "2x", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
JSON

echo "done:"
echo "  $MASTER"
echo "  $ROOT/AppIcon.icns"
echo "  $APPICONSET"
