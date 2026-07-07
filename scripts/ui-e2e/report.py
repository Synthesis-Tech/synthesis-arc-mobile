#!/usr/bin/env python3
"""Summarize an E2E run into report.json for the local dashboard."""
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    out = Path(sys.argv[1])
    exit_code = int(sys.argv[2]) if len(sys.argv) > 2 else 1

    log_path = out / "xcodebuild.log"
    log_text = log_path.read_text() if log_path.exists() else ""

    tests = []
    for m in re.finditer(r"Test Case '-\[(\S+) (\S+)\]' (passed|failed)", log_text):
        tests.append({"class": m.group(1), "name": m.group(2), "status": m.group(3)})

    audit = ""
    audit_path = out / "persisted-audit.log"
    if audit_path.exists():
        audit = audit_path.read_text()[-8000:]

    report = {
        "run_id": out.name,
        "finished_at": datetime.now(timezone.utc).isoformat(),
        "exit_code": exit_code,
        "passed": exit_code == 0,
        "tests": tests,
        "audit_tail": audit,
        "artifacts": {
            "xcodebuild_log": str(log_path),
            "xcresult": str(out / "Results.xcresult"),
            "audit_log": str(audit_path) if audit_path.exists() else None,
        },
    }

    (out / "report.json").write_text(json.dumps(report, indent=2))

    # Update dashboard index
    root = out.parent.parent
    index_path = root / "runs" / "index.json"
    index_path.parent.mkdir(parents=True, exist_ok=True)
    runs = []
    if index_path.exists():
        runs = json.loads(index_path.read_text())
    runs = [r for r in runs if r.get("run_id") != out.name]
    runs.insert(0, {"run_id": out.name, "passed": report["passed"], "finished_at": report["finished_at"], "path": str(out)})
    index_path.write_text(json.dumps(runs[:30], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())