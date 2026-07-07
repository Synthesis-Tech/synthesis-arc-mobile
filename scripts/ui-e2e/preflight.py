#!/usr/bin/env python3
"""Verify graphd is reachable with E2E credentials before launching UI tests."""
import json
import os
import sys
import urllib.error
import urllib.request


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else None
    host = os.environ["FORGE_GRAPH_HOST"]
    port = os.environ.get("FORGE_GRAPH_PORT", "9090")
    key = os.environ["FORGE_GRAPH_API_KEY"]
    agent = os.environ["FORGE_GRAPH_AGENT"]
    base = f"http://{host}:{port}"

    report = {"base": base, "agent": agent, "checks": {}}

    def get(path: str) -> tuple[int, str]:
        req = urllib.request.Request(f"{base}{path}")
        req.add_header("Authorization", f"ApiKey {key}")
        req.add_header("X-Agent-Id", agent)
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                return resp.status, resp.read(500).decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, e.read(500).decode("utf-8", "replace")

    code, _ = get("/health")
    report["checks"]["health"] = code
    if code != 200:
        print(f"health failed: HTTP {code}")
        _write(out, report)
        return 1

    code, body = get("/api/v1/channels/list")
    report["checks"]["channels_list"] = code
    if code != 200:
        print(f"channels/list failed: HTTP {code} {body[:200]}")
        _write(out, report)
        return 1

    try:
        channels = json.loads(body)
        report["channel_count"] = len(channels)
    except json.JSONDecodeError:
        report["channel_count"] = -1

    print(f"preflight OK — {report.get('channel_count', '?')} channels at {base}")
    _write(out, report)
    return 0


def _write(path: str | None, data: dict) -> None:
    if not path:
        return
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


if __name__ == "__main__":
    raise SystemExit(main())