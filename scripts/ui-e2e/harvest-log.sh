#!/usr/bin/env bash
# Pull persisted coordination-audit.log from the booted simulator app container.
set -euo pipefail

OUT="${1:?usage: harvest-log.sh <run-dir>}"
BUNDLE="com.synthesisarc.SynthesisArc-iOS"
UDID="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((x["udid"] for devs in d["devices"].values() for x in devs if x["state"]=="Booted"), ""))')"

if [[ -z "$UDID" ]]; then
  echo "WARN: no booted simulator — skip log harvest" >&2
  exit 0
fi

CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null || true)"
LOG_PATH="$CONTAINER/Library/Application Support/coordination-audit.log"

if [[ -f "$LOG_PATH" ]]; then
  cp "$LOG_PATH" "$OUT/persisted-audit.log"
  echo "Harvested audit log → $OUT/persisted-audit.log"
else
  echo "WARN: no persisted audit log at $LOG_PATH" >&2
fi