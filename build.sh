#!/bin/bash
# Builds "AE Timeline Zoom.app" into ./build and signs it ad-hoc so macOS keeps a
# stable identity for the Accessibility grant.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/AE Timeline Zoom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

xcrun swiftc -O \
    Sources/AETimelineZoom/*.swift \
    -o "$APP/Contents/MacOS/AETimelineZoom" \
    -framework Cocoa -framework ApplicationServices

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier local.ae.timelinezoom "$APP" >/dev/null 2>&1 || true
echo "built: $APP"

if [ "${1:-}" = "--install" ]; then
    DEST="/Applications/AE Timeline Zoom.app"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "installed: $DEST"
fi
