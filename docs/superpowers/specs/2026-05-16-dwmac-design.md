# dwmac — Design

A headless macOS LaunchAgent that auto-tiles every window into three fixed zones per screen — left stack, center main, right stack — and is driven entirely by global keyboard shortcuts in the style of dwm.

## Concept

* The screen is partitioned into three vertical zones at all times: `[ left stack | MAIN | right stack ]`.
* MAIN holds at most one window, centered.
* Each stack holds zero or more windows tiled top-to-bottom with equal height.
* If a side stack is empty, its zone is simply left blank — the main does not expand to fill it.
* New non-main windows fill the **left** stack first, then the **right** stack, then continue to alternate to keep the stacks balanced.
* The user never drags windows; hotkeys do everything.

## Default hotkey map (Mod = Ctrl+Cmd, configurable)

| Combo | Action |
|---|---|
| `Mod+J` / `Mod+K` | Focus next / prev tiled window on the current screen+workspace |
| `Mod+Return` | Swap the focused window with the main window |
| `Mod+H` / `Mod+L` | Shrink / grow MAIN by 5% of screen width (clamped to 30–80%) |
| `Mod+Shift+H` / `Mod+Shift+L` | Send focused window into the left / right stack |
| `Mod+R` | Re-tile the current screen |
| `Mod+T` | Toggle tiling on/off for the current screen |
| `Mod+F` | Toggle floating for the focused window |
| `Mod+,` / `Mod+.` | Focus prev / next monitor |
| `Mod+Shift+,` / `Mod+Shift+.` | Move focused window to prev / next monitor |
| `Mod+1` … `Mod+9` | Switch the current screen to workspace N |
| `Mod+Shift+1` … `Mod+Shift+9` | Send focused window to workspace N |
| `Mod+Shift+C` | Close focused window |
| `Mod+Shift+Q` | Quit dwmac |

## Layout math

Given `visibleFrame` of a screen `S` (excludes menu bar + Dock) and main fraction `m ∈ [0.30, 0.80]`:

```
outerGap = 8
innerGap = 6

usable.x = S.x + outerGap
usable.y = S.y + outerGap
usable.w = S.w - 2*outerGap
usable.h = S.h - 2*outerGap

mainW    = floor(usable.w * m)
sideW    = floor((usable.w - mainW - 2*innerGap) / 2)

main.x   = usable.x + sideW + innerGap
main.y   = usable.y
main.w   = mainW
main.h   = usable.h

left.x   = usable.x
left.y   = usable.y
left.w   = sideW
left.h   = usable.h

right.x  = main.x + main.w + innerGap
right.y  = usable.y
right.w  = sideW
right.h  = usable.h
```

Within a side stack of `n` windows, each window has height `(zone.h - (n-1)*innerGap) / n` and is stacked top-to-bottom with `innerGap` between them.

## New window placement rule

1. If the screen+workspace has no MAIN, the new window becomes MAIN.
2. Otherwise, pick the side stack with fewer windows; ties go **left** (matches the user's preferred fill order).
3. The window is appended at the bottom of that stack.

## Workspaces

* 9 workspaces, numbered 1 through 9.
* Workspaces are dwmac-internal and orthogonal to macOS Spaces.
* Every window has a `(screenID, workspace)` assignment.
* Only windows whose workspace matches the screen's current workspace are visible+tiled. Off-workspace windows are "parked" at an off-screen position so macOS does not animate them between Spaces.
* Switching a screen's workspace unparks all windows of the new workspace, parks all windows of the old workspace, and re-tiles.

## Floating-by-default rules

The tiler skips windows that match any of:

* AX role `AXSheet`, AX subrole `AXDialog` or `AXFloatingWindow`.
* Minimum size < 200×200 px.
* Bundle ID in the float denylist. Defaults: `com.apple.systempreferences`, `com.apple.ScreenSaver.Engine`, plus Finder's open/save panels (matched on subrole).
* User-pinned float (`Mod+F`) — overrides everything else.

Floating windows are still tracked in the store but excluded from layout.

## Configuration file

`~/.config/dwmac/config.json`, created from defaults on first launch.

```json
{
  "modifier": ["control", "command"],
  "mainFraction": 0.6,
  "mainFractionMin": 0.30,
  "mainFractionMax": 0.80,
  "mainFractionStep": 0.05,
  "outerGap": 8,
  "innerGap": 6,
  "fillOrder": "left-first",
  "workspaceCount": 9,
  "floatBundleIDs": [
    "com.apple.systempreferences",
    "com.apple.ScreenSaver.Engine"
  ],
  "ignoreBundleIDs": [],
  "logLevel": "info"
}
```

Modifier tokens accepted: `control`, `command`, `option`, `shift`. Order is irrelevant. `ignoreBundleIDs` are not managed at all — neither tiled nor parked. Reload requires restarting the LaunchAgent.

## Components

```
Sources/dwmac/
├── main.swift                       — bootstrap + RunLoop
├── Config/
│   └── Config.swift                 — Codable config + defaults + load/create
├── Permissions/
│   └── Accessibility.swift          — AXIsProcessTrustedWithOptions
├── Hotkeys/
│   ├── HotkeyManager.swift          — register/unregister, dispatch
│   └── CarbonBridge.swift           — RegisterEventHotKey wrapper
├── Windows/
│   ├── WindowAdapter.swift          — AXUIElement wrapper (frame/focus/close)
│   ├── WindowStore.swift            — id ↔ window + workspace assignment
│   └── WindowObserver.swift         — AXObserver + NSWorkspace notifications
├── Layout/
│   ├── Layout.swift                 — 3-zone math
│   └── ScreenState.swift            — per-screen main width, workspace, tiling on/off
├── Workspaces/
│   └── WorkspaceManager.swift       — park/unpark, switch
├── Commands/
│   └── Commands.swift               — action map
└── Util/
    ├── Logger.swift                 — file + stderr logger
    └── GeometryUtil.swift           — CGRect helpers
```

## Data flow

1. **Boot:** load config → check AX trust (prompt + non-zero exit if missing — LaunchAgent throttles and retries) → enumerate running apps' windows via `NSWorkspace.shared.runningApplications` and the AX API → assign each window to its screen + workspace 1 → register hotkeys → tile every screen.
2. **Window created:** `kAXWindowCreatedNotification` from each app's `AXObserver` → add to store → apply new-window rule → tile its screen.
3. **Window destroyed:** observer notification → remove → tile screen.
4. **Window moved/resized externally:** observer notification → if still tiled, snap back to its computed slot (no fight loop; ignore events caused by our own writes via a one-shot suppression flag).
5. **App launched:** `NSWorkspace.shared.notificationCenter` → attach an `AXObserver` to that app, enumerate its windows.
6. **App terminated:** detach observer, evict its windows.
7. **Hotkey fired:** Carbon callback on main RunLoop → dispatch to a command closure → mutate state → tile affected screens.
8. **Screen arrangement changes:** `NSApplication.didChangeScreenParametersNotification` → reassign windows to nearest screen by midpoint → re-tile.

## Errors and recovery

| Condition | Handling |
|---|---|
| Accessibility not granted | Log instructions, exit non-zero. LaunchAgent ThrottleInterval=10 retries. |
| Hotkey registration fails (conflict with another app) | Log warning, continue without that binding. |
| `AXUIElementSetAttributeValue` fails for a window (Electron, web view, etc.) | Log debug, mark window as `axHostile`, skip on future tiles. |
| Config JSON invalid | Log file:line, fall back to in-memory defaults. |
| Display reconfiguration mid-frame | Coalesce; re-tile once after a 100 ms debounce. |
| Process killed (SIGTERM, SIGINT) | Trap, unregister hotkeys, exit 0 — LaunchAgent will not restart for exit 0. |

## Artifacts shipped

* `dwmac` binary, built with `swift build -c release`.
* `scripts/install.sh` — builds, copies binary to `~/.local/bin/dwmac`, writes `~/Library/LaunchAgents/com.dwmac.agent.plist`, runs `launchctl bootstrap gui/$UID …`.
* `scripts/uninstall.sh` — `launchctl bootout`, remove plist + binary.
* `LaunchAgent/com.dwmac.agent.plist` template — KeepAlive (SuccessfulExit=false), RunAtLoad, ThrottleInterval=10, stdout/stderr → `~/Library/Logs/dwmac.log`.
* `README.md` — install, permissions, hotkey reference, config example.

## Out of scope (v1)

* GUI / menu bar item.
* Layouts other than the 3-zone master+L+R.
* Hot-reload of config (must `launchctl kickstart -k gui/$UID/com.dwmac.agent`).
* Window animations / smooth resize.
* Multi-monitor configurations where workspaces span monitors. Workspaces are strictly per-screen.
* Codesigning / notarization. The user runs an ad-hoc-signed local binary.

## Test plan

* Unit tests for `Layout` (math), `Config` (parse/defaults), `GeometryUtil`, `WorkspaceManager` (park positions).
* Manual smoke checklist in `README.md` covering each hotkey on a single-monitor + two-monitor setup.
* The build must produce a binary that launches, prompts for AX, and registers all default hotkeys without errors when AX is granted.
