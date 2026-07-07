#!/usr/bin/env bash
# Forge Commander UI E2E — build, run XCUITest on iPad simulator, harvest logs, write report.
#
# Setup:
#   cp config/e2e.env.example config/e2e.env
#   # edit config/e2e.env with your API key
#
# Run:
#   ./scripts/ui-e2e/run.sh
#   ./scripts/ui-e2e/run.sh --test test02_openEngineeringChannel
#
# Dashboard:
#   ./scripts/ui-e2e/serve-dashboard.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ENV_FILE="${E2E_ENV_FILE:-$ROOT/config/e2e.env}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$ROOT/.ui-e2e/runs/$RUN_ID"
SCHEME="SynthesisArc_iOS"
SIM_NAME="${E2E_SIM_NAME:-iPad Pro 13-inch (M5)}"
TEST_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --test) TEST_FILTER="-only-testing:SynthesisArcUITests/ForgeCommanderE2ETests/$2"; shift 2 ;;
    --env) ENV_FILE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Missing $ENV_FILE" >&2
  echo "Copy config/e2e.env.example → config/e2e.env and add your API key." >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

export FORGE_E2E=1
export FORGE_GRAPH_HOST
export FORGE_GRAPH_PORT="${FORGE_GRAPH_PORT:-9090}"
export FORGE_GRAPH_API_KEY
export FORGE_GRAPH_AGENT

for var in FORGE_GRAPH_HOST FORGE_GRAPH_API_KEY FORGE_GRAPH_AGENT; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var not set in $ENV_FILE" >&2
    exit 1
  fi
done

export FORGE_E2E=1
mkdir -p "$OUT"

echo "==> UI E2E run $RUN_ID"
echo "    graphd: ${FORGE_GRAPH_HOST}:${FORGE_GRAPH_PORT:-9090}"
echo "    agent:  ${FORGE_GRAPH_AGENT}"
echo "    sim:    ${SIM_NAME}"
echo "    out:    $OUT"

echo "==> xcodegen generate"
xcodegen generate

echo "==> API preflight"
python3 "$ROOT/scripts/ui-e2e/preflight.py" "$OUT/preflight.json" || {
  echo "ERROR: graphd preflight failed — fix config/e2e.env before UI tests" >&2
  exit 1
}

BUNDLE_ID="com.synthesisarc.SynthesisArc-iOS"
SIM_UDID="$(xcrun simctl list devices available -j | python3 -c "
import json,sys
name=sys.argv[1]
data=json.load(sys.stdin)
for devs in data.get('devices',{}).values():
    for d in devs:
        if d.get('name')==name and d.get('isAvailable'):
            print(d['udid']); raise SystemExit
raise SystemExit(1)
" "$SIM_NAME" 2>/dev/null || true)"

if [[ -n "$SIM_UDID" ]]; then
  echo "==> reset app data on simulator $SIM_UDID"
  xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
fi

echo "==> xcodebuild test"
set +e
env FORGE_E2E=1 \
  E2E_ENV_FILE="$ENV_FILE" \
  SRCROOT="$ROOT" \
  FORGE_GRAPH_HOST="$FORGE_GRAPH_HOST" \
  FORGE_GRAPH_PORT="${FORGE_GRAPH_PORT:-9090}" \
  FORGE_GRAPH_API_KEY="$FORGE_GRAPH_API_KEY" \
  FORGE_GRAPH_AGENT="$FORGE_GRAPH_AGENT" \
  xcodebuild test \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=${SIM_NAME}" \
  -resultBundlePath "$OUT/Results.xcresult" \
  $TEST_FILTER \
  FORGE_E2E=1 \
  FORGE_GRAPH_HOST="$FORGE_GRAPH_HOST" \
  FORGE_GRAPH_PORT="${FORGE_GRAPH_PORT:-9090}" \
  FORGE_GRAPH_API_KEY="$FORGE_GRAPH_API_KEY" \
  FORGE_GRAPH_AGENT="$FORGE_GRAPH_AGENT" \
  2>&1 | tee "$OUT/xcodebuild.log"
XCODE_EXIT=${PIPESTATUS[0]}
set -e

echo "==> harvest simulator audit log"
"$ROOT/scripts/ui-e2e/harvest-log.sh" "$OUT" || true

echo "==> write report"
python3 "$ROOT/scripts/ui-e2e/report.py" "$OUT" "$XCODE_EXIT"

# Update latest symlink for dashboard
ln -sfn "$OUT" "$ROOT/.ui-e2e/latest"

if [[ "$XCODE_EXIT" -ne 0 ]]; then
  echo "FAILED — see $OUT/report.json and $OUT/xcodebuild.log" >&2
  exit "$XCODE_EXIT"
fi

echo "PASSED — report: $OUT/report.json"
echo "Open dashboard: ./scripts/ui-e2e/serve-dashboard.sh"