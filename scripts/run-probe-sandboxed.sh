#!/usr/bin/env bash
# Spike 2: does iTunesLibrary work under App Sandbox?
#
# Build the probe, wrap it in a .app, ad-hoc sign it WITH App Sandbox +
# music-read entitlements (scripts/sandbox.entitlements), and launch via
# LaunchServices. If ITLibrary opens, the sandbox is viable (Mac App Store
# route is on the table). If it fails — or sandboxd denies the
# com.apple.amp.library.framework mach-lookup — that leans toward a direct
# notarized DMG. Output is captured to files because `open` doesn't pipe stdout.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product reclaim-probe >/dev/null
BIN="$(swift build --product reclaim-probe --show-bin-path)/reclaim-probe"

APP="$PWD/.build/reclaim-probe-sandboxed.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/reclaim-probe"
cp "$PWD/Sources/reclaim-probe/Info.plist" "$APP/Contents/Info.plist"
codesign --force --entitlements "$PWD/scripts/sandbox.entitlements" --sign - "$APP"
echo "=== entitlements on the signed bundle ==="
codesign -d --entitlements - "$APP" 2>&1 | grep -iE "sandbox|music|<key>|<true" || true

OUT="$(mktemp /tmp/reclaim-probe-sb.XXXXXX.out)"
ERR="$(mktemp /tmp/reclaim-probe-sb.XXXXXX.err)"
echo "Launching sandboxed $APP ..."
open -W --stdout "$OUT" --stderr "$ERR" "$APP" --args "$@" || true
echo "===== stdout ====="; cat "$OUT"
echo "===== stderr ====="; cat "$ERR"
rm -f "$OUT" "$ERR"
