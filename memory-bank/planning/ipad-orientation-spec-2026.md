# iPad / iPhone Orientation Spec — Synthesis Arc Fleet (INTERNAL)

**Status:** Planning · **Deploy:** iOS 27 / iPadOS 27 internal only · **Tailscale:** excluded (manual host in Settings)

## Shell routing

| Device | Primary | Shell |
|--------|---------|-------|
| iPhone | Portrait | 6-tab `TabView`, all orientations |
| iPad | Landscape | `NavigationSplitView` 3-column command center |

Route on `horizontalSizeClass`, not idiom. Compact (Slide Over) → phone shell.

## iPad landscape (primary)

```
[Command rail 44pt — full width above content columns]
[Sidebar 280pt | Center flex | Inspector 320-380pt]
```

## Rotation

Preserve: sidebar selection, `selectedPeer`, conversation/channel selection, composer drafts. Never clear on rotate.

## Per-view summary

See agent expansions in conversation 2026-06-16. Key locks:

- **Fleet iPad L:** 4-6 col grid, selection → inspector, no sheets for DM
- **Inbox/Channels iPad L:** list col 1, thread col 2
- **Director iPad L:** ops read content, broadcast form detail
- **Blackboard iPad L:** list content, entry inspector detail
- **Settings iPad L:** connection form content, prefs detail
- **iPhone L:** composer pinned; thread shrinks; 1-line reply field in channels

## Phases

1. Size-class router + iPad fleet 3-col
2. Inbox/Channels split
3. Command rail + rotation state
4. iPhone landscape composer rules
5. Director/Blackboard/Settings split