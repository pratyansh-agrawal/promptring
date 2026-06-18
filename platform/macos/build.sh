#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  promptring — build the notification agent app
# ════════════════════════════════════════════════════════════════════
#  Compiles src/main.swift into a self-contained, ad-hoc–signed
#  Promptring.app bundle. Run once (install.sh calls this automatically
#  when the app is missing). Requires Xcode Command Line Tools.
#
#  Output:  app/Promptring.app
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ICON="$REPO/app/icon.png"            # shared horn icon (used by every platform)
APP="$HERE/Promptring.app"
MACOS_DIR="$APP/Contents/MacOS"
BIN="$MACOS_DIR/promptring"

# ── preflight ───────────────────────────────────────────────────────
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "error: Swift compiler not found. Install the Command Line Tools:" >&2
  echo "       xcode-select --install" >&2
  exit 1
fi

echo "promptring app build"
echo "  swiftc: $(xcrun --find swiftc)"

# ── assemble the bundle skeleton ────────────────────────────────────
rm -rf "$APP"
mkdir -p "$MACOS_DIR"
RES_DIR="$APP/Contents/Resources"
mkdir -p "$RES_DIR"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

# ── app icon ────────────────────────────────────────────────────────
#  Generate icon.icns from icon.png (the promptring horn logo). The
#  source isn't square, so center-crop it to a square first, then render
#  every iconset size with `sips` and pack with `iconutil`.
if [ -f "$ICON" ] && command -v sips >/dev/null 2>&1; then
  ICONSET="$(mktemp -d)/icon.iconset"
  mkdir -p "$ICONSET"
  # center-crop to a square using the smaller dimension
  W="$(sips -g pixelWidth  "$ICON" | awk '/pixelWidth/{print $2}')"
  H="$(sips -g pixelHeight "$ICON" | awk '/pixelHeight/{print $2}')"
  SIDE=$(( W < H ? W : H ))
  SQUARE="$(mktemp -d)/square.png"
  sips -c "$SIDE" "$SIDE" "$ICON" --out "$SQUARE" >/dev/null
  for sz in 16 32 128 256 512; do
    sips -z "$sz" "$sz"           "$SQUARE" --out "$ICONSET/icon_${sz}x${sz}.png"    >/dev/null
    sips -z $((sz*2)) $((sz*2))   "$SQUARE" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RES_DIR/icon.icns"
  echo "  icon    → $RES_DIR/icon.icns"
else
  echo "  icon    → skipped (icon.png or sips missing)"
fi

# ── compile ─────────────────────────────────────────────────────────
xcrun swiftc -O \
  -framework Cocoa \
  -framework UserNotifications \
  -o "$BIN" \
  "$HERE/src/main.swift"
chmod +x "$BIN"
echo "  compiled → $BIN"

# ── ad-hoc code sign (required for UserNotifications identity) ───────
#  "-" is the ad-hoc identity: valid on THIS machine without an Apple
#  Developer account. Distribution to others requires a local rebuild
#  (or proper notarization, which needs a paid Developer ID).
#
#  Note: iCloud-synced folders (e.g. ~/Documents) keep re-adding xattrs
#  (FinderInfo / fileprovider) that codesign rejects, so clear them
#  thoroughly — bundle root + every nested file — right before signing.
xattr -cr "$APP" 2>/dev/null || true
find "$APP" -exec xattr -c {} \; 2>/dev/null || true
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
echo "  ad-hoc signed → $APP"

echo ""
echo "Built $APP"
echo "Test it:"
echo "  \"$BIN\" --title \"✅ Promptring\" --subtitle \"Build OK\" --message \"hello\""
