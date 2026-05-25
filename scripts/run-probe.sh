#!/usr/bin/env bash
# Build the reclaim-probe executable, wrap it in a minimal ad-hoc-signed .app
# bundle, and launch it via LaunchServices so macOS attributes the
# Media & Apple Music (TCC) request to the bundle and can show the permission
# prompt. A bare `swift run` of the executable fails with NSCocoaErrorDomain
# 4097 ("Couldn't communicate with a helper application") because the
# iTunesLibrary XPC service rejects a non-bundled client. Output is captured to
# files because `open` does not pipe stdout back to the terminal.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product reclaim-probe >/dev/null
BIN="$(swift build --product reclaim-probe --show-bin-path)/reclaim-probe"

APP="$PWD/.build/reclaim-probe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/reclaim-probe"
cp "$PWD/Sources/reclaim-probe/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

OUT="$(mktemp /tmp/reclaim-probe.XXXXXX.out)"
ERR="$(mktemp /tmp/reclaim-probe.XXXXXX.err)"
echo "Launching $APP — if a 'wants to access Apple Music' prompt appears, click Allow."
# Any args after the script name are forwarded to the probe as a search filter.
open -W --stdout "$OUT" --stderr "$ERR" "$APP" --args "$@"
echo "===== stdout ====="; cat "$OUT"
if [ -s "$ERR" ]; then echo "===== stderr ====="; cat "$ERR"; fi
rm -f "$OUT" "$ERR"
