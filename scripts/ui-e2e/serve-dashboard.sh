#!/usr/bin/env bash
# Serve the local UI E2E dashboard on http://127.0.0.1:8765
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$ROOT/.ui-e2e/runs"
cp -f "$ROOT/scripts/ui-e2e/dashboard/index.html" "$ROOT/.ui-e2e/index.html"
cd "$ROOT/.ui-e2e"
echo "Dashboard: http://127.0.0.1:8765/"
echo "Runs dir:  $ROOT/.ui-e2e/runs/"
python3 -m http.server 8765 --bind 127.0.0.1