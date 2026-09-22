#!/bin/bash
# Builds Marko.app — a native macOS wrapper for the Marko viewer.
#
#   app/mac/build.sh              → app/mac/build/Marko.app  (ad-hoc signed; runs on this Mac)
#   app/mac/build.sh --install    → also copies it to /Applications
#   app/mac/build.sh --install --default → …and makes Marko the default app for .md files (no dialog)
#   app/mac/build.sh --dmg        → also produces app/mac/build/Marko-<version>.dmg
#   SIGN_IDENTITY="Developer ID Application: …" app/mac/build.sh --dmg   → signed for distribution (notarize after)
#
# Needs: Xcode Command Line Tools (xcode-select --install) and Node (for the viewer build). No Xcode project.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/build"
APP="$OUT/Marko.app"
VERSION="$(node -p "require('$ROOT/package.json').version")"
BUILD_NO="$(date +%Y%m%d%H%M)"
MIN_OS="12.0"
ARCHS="${ARCHS:-arm64 x86_64}"

echo "▸ Marko.app v$VERSION"
command -v swiftc >/dev/null || { echo "swiftc not found — run: xcode-select --install"; exit 1; }

# 1. Fresh viewer build
( cd "$ROOT" && node scripts/build.js >/dev/null )

# 2. Bundle layout
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/viewer/vendor"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NO/" "$HERE/Info.plist" > "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
cp "$ROOT/docs/guide.md" "$APP/Contents/Resources/guide.md"

# 3. Viewer with the three libraries vendored, so the app is fully offline
VIEWER="$APP/Contents/Resources/viewer/marko.html"
cp "$ROOT/viewer/marko.html" "$VIEWER"
fetch() { # url → local file (skips if already cached in app/mac/vendor-cache)
  local url="$1"
  local name="$2"
  local cache="$HERE/vendor-cache/$name"
  mkdir -p "$HERE/vendor-cache"
  [ -s "$cache" ] || curl -fsSL "$url" -o "$cache"
  cp "$cache" "$APP/Contents/Resources/viewer/vendor/$name"
}
fetch "https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js"           marked.min.js
fetch "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"  highlight.min.js
fetch "https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js"         mermaid.min.js
sed -i '' \
  -e 's#https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js#vendor/marked.min.js#' \
  -e 's#https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js#vendor/highlight.min.js#' \
  -e 's#https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js#vendor/mermaid.min.js#' \
  "$VIEWER"

# 4. Icon (.icns from icon.png)
ICONSET="$OUT/Marko.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$HERE/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$HERE/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Marko.icns"
rm -rf "$ICONSET"

# 5. Compile (universal by default)
BINS=()
for arch in $ARCHS; do
  echo "▸ compiling ($arch)"
  swiftc -O -target "$arch-apple-macos$MIN_OS" \
    -framework Cocoa -framework WebKit -framework UniformTypeIdentifiers \
    -o "$OUT/Marko-$arch" "$HERE/main.swift"
  BINS+=("$OUT/Marko-$arch")
done
if [ ${#BINS[@]} -gt 1 ]; then lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/Marko"; else cp "${BINS[0]}" "$APP/Contents/MacOS/Marko"; fi
rm -f "${BINS[@]}"
strip -x "$APP/Contents/MacOS/Marko" 2>/dev/null || true

# 6. Sign (ad-hoc unless SIGN_IDENTITY is set)
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
echo "▸ built $APP ($(du -sh "$APP" | cut -f1)), signed as: $IDENTITY"

# 7. Optional install / DMG
for arg in "$@"; do
  case "$arg" in
    --install)
      rm -rf "/Applications/Marko.app"; cp -R "$APP" /Applications/
      echo "▸ installed to /Applications/Marko.app"
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Marko.app >/dev/null 2>&1 || true
      case " $* " in *" --default "*)
        /Applications/Marko.app/Contents/MacOS/Marko --set-default >/dev/null 2>&1 && echo "▸ Marko is now the default app for Markdown files" || echo "▸ could not set default automatically — use Marko ▸ Make Default for Markdown Files" ;;
      esac ;;
    --dmg)
      DMG="$OUT/Marko-$VERSION.dmg"; STAGE="$OUT/dmg"; rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
      cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
      hdiutil create -volname "Marko" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
      rm -rf "$STAGE"
      if [ "$IDENTITY" != "-" ]; then codesign --sign "$IDENTITY" "$DMG"; fi
      echo "▸ $DMG" ;;
  esac
done
echo "done. Run it:  open \"$APP\" path/to/file.md"
