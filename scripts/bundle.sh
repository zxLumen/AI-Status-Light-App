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

# Sign with a *stable* identity so macOS TCC permissions (Accessibility /
# Automation) persist across rebuilds. Falls back to ad-hoc when unavailable.
IDENTITY="${AISTATUS_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)}"
if [ -n "${IDENTITY:-}" ]; then
  if codesign --force --deep --sign "$IDENTITY" --timestamp=none "$APP" >/dev/null 2>&1; then
    echo "signed with: $IDENTITY"
  else
    echo "stable signing failed; falling back to ad-hoc"
    codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
  fi
else
  codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
fi

echo "built: $APP"
