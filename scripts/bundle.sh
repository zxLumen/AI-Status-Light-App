#!/usr/bin/env bash
# Build the SwiftPM executable and assemble a runnable .app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
CONFIG=release

swift build -c "$CONFIG"

APP="build/AI Status Light.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/$CONFIG/AIStatusLight" "$APP/Contents/MacOS/AIStatusLight"
cp "$ROOT/aistatus/states.json" "$APP/Contents/Resources/states.json"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature so the bundle launches locally without a Developer ID.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
