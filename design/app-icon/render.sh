#!/bin/bash
# Renders the app icon SVGs into the iPad and macOS asset catalogs and the web favicon.
# Needs resvg (cargo install resvg) and ImageMagick (to drop the alpha channel
# iOS icons must not have).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$DIR/../.." && pwd)"
IPAD="$REPO_DIR/gridstream-ipad/gridstream-ipad/Assets.xcassets/AppIcon.appiconset"
MAC="$REPO_DIR/gridstream-macos/gridstream-macos/Assets.xcassets/AppIcon.appiconset"

for variant in "" -Dark -Tinted; do
  resvg -w 1024 -h 1024 "$DIR/AppIcon$variant.svg" "$IPAD/AppIcon$variant-1024.png"
  magick "$IPAD/AppIcon$variant-1024.png" -background black -alpha remove -alpha off "$IPAD/AppIcon$variant-1024.png"
done

for size in 16 32 128 256 512; do
  resvg -w "$size" -h "$size" "$DIR/AppIcon-macOS.svg" "$MAC/icon_${size}x${size}.png"
  resvg -w $((size * 2)) -h $((size * 2)) "$DIR/AppIcon-macOS.svg" "$MAC/icon_${size}x${size}@2x.png"
done

magick "$MAC/icon_16x16.png" "$MAC/icon_32x32.png" "$MAC/icon_32x32@2x.png" \
  "$REPO_DIR/gridstream-web/public/favicon.ico"
