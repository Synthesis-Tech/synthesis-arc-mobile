# Forge Commander UI E2E Harness

Local simulator automation — no TestFlight, no manual iPad testing.

## Setup (once)

```bash
cp config/e2e.env.example config/e2e.env
# Edit config/e2e.env — set FORGE_GRAPH_API_KEY and host
```

## Run all UI walks

```bash
./scripts/ui-e2e/run.sh
```

## Run one test

```bash
./scripts/ui-e2e/run.sh --test test04_privateChannelJoinFlow
```

## View results dashboard

```bash
./scripts/ui-e2e/serve-dashboard.sh
# open http://127.0.0.1:8765/
```

## What it does

1. **Preflight** — hits graphd `/health` and `/channels/list` with your API key
2. **XCUITest** on iPad Pro simulator (Command Center layout)
3. **Screenshots** per step (in `.ui-e2e/runs/<id>/Results.xcresult`)
4. **Persisted audit log** harvested from simulator after tests
5. **report.json** + local dashboard for agents to review

## Tests

| Test | Walks |
|------|-------|
| `test01_bootAndReachChannels` | Boot → Channels list |
| `test02_openEngineeringChannel` | Open #engineering, assert responsive |
| `test03_createAndOpenChannel` | Create public channel → open |
| `test04_privateChannelJoinFlow` | Create private → join if gated |
| `test05_navigateAllDestinations` | All six nav destinations + screenshots |

## For agents

After a failed run, read:

- `.ui-e2e/latest/report.json`
- `.ui-e2e/latest/persisted-audit.log`
- `.ui-e2e/latest/xcodebuild.log`

No need to navigate the frozen app — logs survive force-quit.