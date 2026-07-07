#!/usr/bin/env bash
# Visual QA — launch Synthesis Arc (macOS), capture tab screenshots for review.
# Usage: ./scripts/visual-qa.sh
# Output: .visual-qa/*.png (gitignored)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.visual-qa"
SCHEME="SynthesisArc_macOS"
APP_NAME="SynthesisArc"

mkdir -p "$OUT"

echo "==> Building $SCHEME"
cd "$ROOT"
xcodegen generate >/dev/null 2>&1 || true
xcodebuild -scheme "$SCHEME" -destination 'platform=macOS' build -quiet

APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Build/Products/Debug/${APP_NAME}.app" \
  -not -path "*iphonesimulator*" 2>/dev/null | head -1)

if [[ -z "$APP" || ! -f "$APP/Contents/MacOS/$APP_NAME" ]]; then
  echo "ERROR: Could not find built $APP_NAME.app" >&2
  exit 1
fi

echo "==> App: $APP"

osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 1
open "$APP"
sleep 4

capture_window() {
  local slug="$1"
  osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 || true
  sleep 1
  local pos
  pos=$(osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to get {position, size} of window 1" 2>/dev/null) || return 1
  local x y w h
  IFS=',' read -r x y w h <<< "$(echo "$pos" | tr -d ' ')"
  local file="$OUT/${slug}.png"
  screencapture -x -R"${x},${y},${w},${h}" "$file"
  echo "    $file ($(du -h "$file" | cut -f1))"
}

click_tab() {
  local name="$1"
  osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to click (first button whose name is \"$name\")" 2>/dev/null || true
  sleep 1
}

echo "==> Capturing tabs"
for tab in Fleet Inbox Channels Director Blackboard Settings; do
  click_tab "$tab"
  capture_window "tab-$(echo "$tab" | tr '[:upper:]' '[:lower:]')" || echo "    WARN: failed $tab"
done

echo "==> Done. Review .visual-qa/ with a visual subagent before shipping UI changes."
ls -la "$OUT"