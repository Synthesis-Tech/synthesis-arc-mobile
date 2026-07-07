# Director Scratchpad — Synthesis Arc Mobile
**Updated:** 2026-06-17 · **Mode:** Oversight / delegate-only

> Living doc. Director updates at phase boundaries. Agents write to task outputs; director merges here.

## Current phase
**SPEC COMPLETE (internal iPad 27)** — all orientation phases + validation P0/P1 wired. Smoke test passed. Ready for operator review.

## Last action
Full spec completion pass: channel reply_to, per-sender unread, drafts/rotation, iPhone landscape composer, Mac command center, background poll, settings split. `scripts/smoke-test-ios.sh` **SMOKE OK**. See `ipad-spec-completion-2026.md`.

## Open decisions
- [ ] Start Phase 1 implementation now vs QA script first?
- [ ] `mind_board` REST bridge — defer until shell ships?
- [ ] Lattice GUI integration — defer Phase 2+?

## P0 queue (copy for delegates)
1. ~~CommandCenterState + horizontalSizeClass router~~ DONE
2. ~~NavigationSplitView fleet 3-col~~ DONE (iPad regular width)
3. ~~Inspector by agentName~~ DONE
4. ~~Notification deep links~~ DONE (userInfo + synthesisarc:// + delegate)
5. ~~Settings Apply & Reconnect~~ DONE
6. ~~Mac command center (carry iPad shell)~~ DONE
7. ~~Top command rail (44pt metrics bar)~~ DONE
8. Inbox/channels/blackboard/director split columns — DONE
9. Fleet inline DM (no sheet) — DONE
10. markDelivered on inbox open — DONE
11. Channel row unread + preview — DONE
12. Watchlist in exceptionCount — DONE

## Acceptance (internal iPad 27)
See `memory-bank/planning/ipad-validation-report-2026.md` P0 section.

## Agent roster (prometheus-ops domains)
| Domain | Use for |
|--------|---------|
| Design | Orientation, rail, density |
| Engineering | SwiftUI shell, state, APIs |
| Operations | UC evals, operator flows |
| Research | Platform/iPadOS 27 APIs |
| Blind validator | Pre-ship adversarial pass |

## Do NOT
- Wide filesystem glob
- Embed Tailscale
- Assume spec is implemented (~24% fidelity)
- Implement large features in director thread — delegate

## Session log (compact)
| When | What |
|------|------|
| 2026-06-16 | Reply routing + UI polish shipped (user confirmed) |
| 2026-06-16 | iOS build fixed (Info.plist duplicate) |
| 2026-06-16 | iPad spec + 7 orientation agents + 4 blind validators |
| 2026-06-16 | Director mode requested — this scratchpad created |

## Phase 1 files
`SynthesisArc/State/CommandCenterState.swift`, `SynthesisArc/Views/Shell/*`

## Next director move
1. User test iPad landscape on device/sim
2. Phase 1.5: inbox/channels split, command rail, deep links
3. Then macOS `CommandCenterShellView` (same shell, `horizontalSizeClass` or min width on macOS)
4. Blind validator on Phase 1 diff before internal deploy

## Note
User upgraded Grok Heavy (90d). **Xcode MCP wired** — `.grok/config.toml` + `.cursor/mcp.json` → `xcrun mcpbridge` (21 tools, doctor OK 2026-06-17). Requires Xcode open + Intelligence → allow external agents.