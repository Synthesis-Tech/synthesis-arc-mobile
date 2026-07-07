# Forge Commander — July 2026 Improvement Sprint

> **Director dispatch:** 2026-07-07  
> **Goal:** Stop field-QA pain; ship Slack-density UX on iPad; make regressions impossible before TestFlight.

**Repo:** `synthesis-arc-mobile` (Forge Commander iOS/macOS)  
**Backend:** forge-graphd `:9090` via Tailscale  
**Test gate:** `scripts/ui-e2e/run.sh` (landscape iPad sim, `config/e2e.env`)

---

## Current state (post build 22)

| Area | Status |
|------|--------|
| 3-column iPad shell | ✅ `CommandCenterShellView` |
| DM persistence + hydration | ✅ `DMThreadPersistence`, node fetch |
| Inbox Slack rows | ✅ avatars, unread bold, `inboxPreview` |
| Automatic issue logging | ✅ `UsabilityTrace` → blackboard (not on TF until build 23+) |
| Channel join lockup | ⚠️ patched, not verified in E2E |
| E2E channel tests | ❌ test02–04 fail (thread never mounts) |
| Channel list previews | ❌ no Slack-style last message / unread |
| In-channel `reply_to` | ⚠️ API wired, UX partial |
| graphd DM history API | ❌ poll-only inbound |
| API key storage | ⚠️ UserDefaults, not Keychain |
| Push → deep link | ⚠️ partial |

---

## Sprint tracks (parallel)

### Track A — Reliability Lead (P0)
**Owner:** Agent A  
**Mission:** Green E2E channel tests; thread mounts within 20s every time.

**Files:**
- `SynthesisArc/Services/ChannelService.swift`
- `SynthesisArc/Views/ChannelsView.swift`
- `SynthesisArc/Views/Shell/ChannelsCommandCenterView.swift`
- `SynthesisArcUITests/ForgeCommanderE2ETests.swift`
- `scripts/ui-e2e/run.sh`

**Acceptance:**
- `test02_openEngineeringChannel` PASS
- `test03_createAndOpenChannel` PASS
- `test04_privateChannelJoinFlow` PASS
- No spinner lockup after join on engineering channel

**Known hypothesis:** Inspector `ChannelThreadView` `.task` races with `setActiveChannel`; `activeMessages` not published before assert; E2E `channel.thread` a11y id missing or not visible in split column.

---

### Track B — Channels UX Lead (P1)
**Owner:** Agent B  
**Mission:** Slack-style channel list — preview line + per-channel unread badge.

**Files:**
- `SynthesisArc/Services/ChannelService.swift` (`channelPreviews`, `channelUnread`)
- `SynthesisArc/Views/Shell/ChannelsCommandCenterView.swift`
- `SynthesisArc/Views/ChannelsView.swift` (list rows)
- Mirror patterns from `RecentConversationsSection.swift`

**Acceptance:**
- Each channel row: `#name — sender: preview…` + relative time
- Unread badge when `channelUnread[name] > 0`
- Preview uses readable body (no raw `msg/id`)

---

### Track C — Platform Lead (P1)
**Owner:** Agent C  
**Mission:** Notification tap → correct thread; resilient reconnect.

**Files:**
- `SynthesisArc/Services/PushNotificationService.swift`
- `SynthesisArc/Services/DeepLinkCoordinator.swift`
- `SynthesisArc/Services/FleetService.swift` (`applySettingsAndReconnect`)
- `SynthesisArc/Services/CoordinationStreamService.swift`
- `SynthesisArc/Views/ConnectionStatusBar.swift`

**Acceptance:**
- Push payload routes to inbox channel or DM without manual nav
- Settings save → boot + SSE within 30s (visible status)
- Document gaps in sprint report if graphd changes needed

---

## Sequential (after A is green)

| ID | Task | Priority |
|----|------|----------|
| D1 | Deploy build 23+ to TestFlight only after E2E green | P0 |
| D2 | graphd `GET /messages/history?peer=` or document blackboard fallback | P1 |
| D3 | Keychain migration for API key | P2 |
| D4 | OpenObserve alerts on `ops/field-trace/*` signatures | P2 |
| D5 | Unified search (agents + channels) | P2 |

---

## Global constraints

- Do **not** deploy TestFlight unless user explicitly asks
- E2E credentials: `config/e2e.env` (gitignored), `FORGE_GRAPH_*` vars
- `project.yml` is source of truth — run `xcodegen generate` after new files
- No message bodies in telemetry; usability tracing only
- Swift 6, iOS 17+, scheme `SynthesisArc_iOS`

---

## Verification commands

```bash
# Full E2E
./scripts/ui-e2e/run.sh

# Single test
./scripts/ui-e2e/run.sh --test test02_openEngineeringChannel

# Local build
xcodegen generate && xcodebuild -scheme SynthesisArc_iOS \
  -destination 'generic/platform=iOS Simulator' build
```

---

## Reporting

Each track agent returns:
1. **Done / blocked** with evidence (test output or screenshot path)
2. **Files changed** (list)
3. **Risks** for merge with other tracks
4. **Next 1–2 tasks** if time remains

Director integrates → user gets single sitrep.

---

## Sitrep — 2026-07-07 (team dispatched)

### Track A — Reliability (in progress)
- Fixed E2E launch deadlock (`AppConfig` init → audit log re-entry)
- Channel inspector eager `openChannelThread` + force history reload
- E2E `channel.thread` query broadened
- **Pending:** confirm `test02` green, then test03/04

### Track B — Channel Slack rows (done)
- `#channel — sender: preview` + unread badge + relative time
- `ChannelPreview` uses `inboxPreview` / `readableBody`
- Files: `Models.swift`, `ChannelService.swift`, `ChannelsView.swift`

### Track C — Platform (done)
- Deep link → inbox hydrate + channel `setActiveChannel` + `openChannelThread`
- Connection bar shows real reconnecting state (not false green Live)
- Apply & Reconnect SSE wait 30s; flexible push `userInfo` parsing
- 12 files touched (see Track C agent report)

### Next director action
1. Run full E2E gate: `./scripts/ui-e2e/run.sh`
2. Merge conflict check across A/B/C file overlap (`ChannelsView`, `ChannelService`)
3. Ship build 23+ to TestFlight when E2E green + user asks