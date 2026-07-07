# iPad Command Center — Blind Validation Report (2026-06-16)

**Method:** Four adversarial agents read source only — no spec assumptions.  
**Spec:** `ipad-orientation-spec-2026.md`  
**Verdict:** ~24% spec fidelity in code today. Data layer mostly ready; UI shell and several flows have P0 gaps.

## P0 blockers (before internal iPad 27 deploy)

1. No `NavigationSplitView` / `horizontalSizeClass` router — iPad is scaled phone `TabView`
2. No notification deep links (`onOpenURL`, notification delegate, `userInfo`)
3. Background alerts unreliable — no `UIBackgroundModes`; SSE stops when suspended
4. Inspector uses snapshot `Peer` — stale under SSE refresh
5. `markDelivered` never called — inbox delivery contract half-wired
6. Settings change doesn't re-boot / restart SSE without manual Retry

## P1 gaps

- Channel `reply_to` API exists but UI routes replies to DM only (`channelReplyHeader` unused)
- Per-channel / per-conversation unread not in list rows
- `exceptionCount` tab badge ignores watchlist (hardcoded `[]`)
- Ops graph is external URL, not graphd
- DM always via sheet on iPad (spec says inline)

## Use case results (today)

| UC | Status |
|----|--------|
| UC1 Morning fleet check | WORKS |
| UC2 Degraded → DM | WORKS (3+ taps) |
| UC3 Channel @mention | PARTIAL (no deep link) |
| UC4 Reply → DM not broadcast | WORKS |
| UC5 Watchlist offline | PARTIAL (poll lag, no push) |
| UC6 Director broadcast | WORKS |
| UC7 iPad 3-col workflow | NOT IMPLEMENTED |
| UC8 Rotate context | PARTIAL |
| UC9 Background notify | PARTIAL |
| UC10 Misconfig recovery | PARTIAL |

## API surface matrix (summary)

| Flow | Client API | Wired E2E |
|------|------------|-----------|
| Boot | POST /peers/boot | YES |
| Fleet refresh | GET peers + blackboard | YES |
| SSE coordination | GET /events/coordination | YES |
| DM send | POST /messages/send | YES |
| Channel reply_to | POST channels/send | NO (UI) |
| markDelivered | POST messages/mark-delivered | NO |
| setBlackboard | PUT /blackboard/{key} | YES (QuickActions only) |
| mind_board | — | ABSENT (correct) |
| Deep link | — | ABSENT |

## Prerequisites for iPad shell merge

1. `CommandCenterState` — selection by `agentName`, not snapshot `Peer`
2. Unify attention: watchlist in `refreshExceptionCount`
3. Per-sender inbox read model (not `markInboxRead` on tab appear)
4. Decouple `setActivePeer` / `setActiveChannel` for multi-column
5. Wire `channelPreviews` + `channelUnread` in ChannelRow
6. Notification payload + routing
7. Apply & Reconnect on settings save

## QA acceptance (P0 excerpt)

- iPad landscape split: fleet + thread visible without tab swap
- UC4 regression: channel reply → DM only, not broadcast
- Notification tap → correct Inbox/Channel/Agent
- Settings fix → Live within 30s without kill
- Degraded → DM E2E under 60s

See full agent transcripts in conversation 2026-06-16.