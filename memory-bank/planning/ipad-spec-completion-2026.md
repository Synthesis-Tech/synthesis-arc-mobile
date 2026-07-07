# iPad Command Center — Spec Completion Report (2026-06-17)

**Method:** Source audit + `xcodebuild` iOS/macOS + simulator install smoke test  
**Verdict:** Spec/plan items **complete for internal iPad 27 deploy** except explicitly deferred integrations. Subagent audit (2026-06-17) drove phone deep-link + BGTask fixes — see `subagent-validation-2026-06-17.md`.

## Orientation spec phases

| Phase | Item | Status |
|-------|------|--------|
| 1 | Size-class router + fleet 3-col | ✅ |
| 2 | Inbox/Channels split | ✅ |
| 3 | Command rail + rotation draft state | ✅ |
| 4 | iPhone landscape composer rules | ✅ |
| 5 | Director/Blackboard/Settings split | ✅ |
| — | Mac command center parity | ✅ |

## Validation P0 (2026-06-16 report)

| # | Blocker | Status |
|---|---------|--------|
| 1 | NavigationSplitView router | ✅ |
| 2 | Notification deep links | ✅ |
| 3 | Background alerts / SSE | ⚠️ Mitigated — `UIBackgroundModes` + foreground/background poll; live SSE still pauses when suspended (iOS) |
| 4 | Live inspector peer resolution | ✅ |
| 5 | markDelivered | ✅ |
| 6 | Settings Apply & Reconnect | ✅ |

## Validation P1

| Item | Status |
|------|--------|
| Channel `reply_to` + `channelReplyHeader` | ✅ Non-DM replies use channel API with `reply_to`; agent-targeted → DM (UC4) |
| Per-row inbox/channel unread | ✅ |
| Watchlist in exceptionCount | ✅ |
| Inline DM on iPad | ✅ Fleet, inbox, channel inspector |
| Ops graph via graphd | ⏸ Deferred — external URL by design |

## Smoke test

```
./scripts/smoke-test-ios.sh → SMOKE OK (build + simctl install)
xcodebuild SynthesisArc_iOS  → BUILD SUCCEEDED
xcodebuild SynthesisArc_macOS → BUILD SUCCEEDED
```

## Explicitly out of scope (prior decisions)

- `mind_board` REST bridge
- Lattice GUI integration
- Tailscale SDK