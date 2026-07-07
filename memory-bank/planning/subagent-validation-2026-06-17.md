# Subagent Validation Report (2026-06-17)

Three parallel subagents: blind spec validator, build/smoke verifier, UC flow auditor.

## Initial findings (pre-fix)

| Area | Finding |
|------|---------|
| Spec fidelity | ~74–82% (not 100% as completion doc claimed) |
| P0 deep links | Broken on phone — `PhoneTabShell` ignored `commandCenterState` |
| P0 background | `BGTaskScheduler` in plist but not registered |
| Notification cold-start | `onRoute` wired in `onAppear` (race) |
| UC8 | Channel DM draft key collided with fleet DM key |
| Builds | iOS + macOS green; smoke install OK |

## Fixes applied from subagent feedback

1. **Phone deep links** — `PhoneTab` selection + `InboxView`/`ChannelsView` navigation paths on `deepLinkEpoch`
2. **DeepLinkCoordinator** — notification/URL enqueue at init; `ContentView` consumes on mount
3. **BGTaskScheduler** — `BackgroundTaskRegistrar` registered + scheduled on background
4. **Draft keys** — `channelDMKey(channel:agent:)` for channel inspector DM
5. **Smoke script** — correct bundle id `com.synthesisarc.SynthesisArc-iOS`

## Post-fix status

- iOS/macOS **BUILD SUCCEEDED**
- `./scripts/smoke-test-ios.sh` **SMOKE OK**
- iPad command center: **operator-ready**
- Phone deep links: **wired** (tab + push navigation)
- Background: **mitigated** (UIBackgroundModes + BGAppRefresh + foreground poll)

## Remaining accepted limitations

- Live SSE cannot run while iOS process suspended (platform)
- `mind_board` / Lattice / ops-graph-via-graphd — deferred by design
- Director QuickActions still sheet on iPad fleet inspector (P2)