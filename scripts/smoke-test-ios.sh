#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="${SMOKE_SCHEME:-SynthesisArc_iOS}"
SIM_ID="${SMOKE_SIM_ID:-091CAE79-B8AC-414F-91D7-F857B48160B8}"
DERIVED="${SMOKE_DERIVED:-/tmp/SynthesisArc-smoke}"

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild ($SCHEME)"
xcodebuild \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DERIVED" \
  build

APP_PATH=""
for candidate in \
  "$DERIVED/Build/Products/Debug-iphonesimulator/SynthesisArc.app" \
  "$DERIVED/Build/Products/Debug-iphonesimulator/Synthesis Arc.app"; do
  if [[ -d "$candidate" ]]; then
    APP_PATH="$candidate"
    break
  fi
done
if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: app bundle not found under $DERIVED/Build/Products/Debug-iphonesimulator" >&2
  ls -la "$DERIVED/Build/Products/Debug-iphonesimulator" 2>/dev/null || true
  exit 1
fi

echo "==> simctl install"
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl install "$SIM_ID" "$APP_PATH"

echo "==> launch"
xcrun simctl launch "$SIM_ID" com.synthesisarc.SynthesisArc-iOS 2>/dev/null || \
  xcrun simctl launch "$SIM_ID" com.synthesisarc.SynthesisArc 2>/dev/null || \
  xcrun simctl launch "$SIM_ID" com.synthesisarc.SynthesisArc_iOS 2>/dev/null || \
  echo "WARN: launch bundle id may differ — install succeeded"

echo "SMOKE OK: build + install"