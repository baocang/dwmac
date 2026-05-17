# dwmac

A headless macOS window manager inspired by [dwm](https://dwm.suckless.org/).
It picks a layout per display:

* **Three-pane** on wide screens (aspect ratio ≥ `wideMinAspectRatio`,
  default 2.0): left · center · right with overlap.
* **Monocle** on every other screen (built-in laptop displays and
  non-wide externals): one window fills the full visible frame, every
  other window stacks centered behind it.

```
wide screen (≥ 2:1):                   non-wide screen / built-in:
┌──────┬───────────────┬──────┐        ┌────────────────────────┐
│      │               │      │        │                        │
│ LEFT │   CENTER      │RIGHT │        │      single window     │
│      │               │      │        │     full visible frame │
└──────┴───────────────┴──────┘        └────────────────────────┘
```

* Each pane holds **one** window, full height.
* Center is wider than the leftover space — it overlaps each side pane by
  about 8% of the screen width. The focused window is z-raised every tile,
  so the focused pane visually covers the overlapping inner edges of its
  neighbors.
* Apps that refuse to resize get **edge-anchored** to the outer edge of their
  slot (left edge for left, right edge for right), so they never slide
  off-screen.
* Windows that don't fit in a slot live in the **hidden pool**, stacked at
  the center zone behind the slot windows. App-activation z-order keeps them
  invisible during normal use. They remain visible in Mission Control and
  Cmd + Tab, where you can pull them into a slot.
* Slots that go empty auto-fill from the pool (FIFO, in order
  center → left → right).
* Dragging a window with the mouse re-slots it by which zone the drop point
  is closest to. The drag is debounced ~300 ms and always re-snaps the
  window back to its slot rect when it settles.
* Focusing a hidden-pool window (Cmd + Tab, Mission Control click, Dock,
  etc.) auto-promotes it to the **center** slot; the previous center is
  demoted back to the pool.

## Requirements

* macOS 13 (Ventura) or newer.
* Xcode command-line tools (Swift 5.9+). Tests need full Xcode.
* Administrator password (one time) to trust the local code-signing identity.

## Install

```sh
git clone https://github.com/<you>/dwmac.git
cd dwmac
./scripts/install-codesign-identity.sh   # one-time: creates the dwmac-signer cert
./scripts/install.sh                     # builds, signs, and starts the agent
```

`install-codesign-identity.sh` generates a self-signed code-signing certificate
called `dwmac-signer` in your login keychain and marks it as trusted in the
system keychain (this is what the `sudo` prompt is for). Every later
`install.sh` signs with that identity, so macOS's TCC database binds the
Accessibility grant to the certificate — your grant survives every rebuild.

The first time the agent runs it will request Accessibility:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Click **`+`**, press **Cmd + Shift + G**, paste
   `/Users/<you>/.local/bin/dwmac`, click Open.
3. Toggle it on.

Force the agent to retry immediately:

```sh
launchctl kickstart -k gui/$(id -u)/com.dwmac.agent
tail -3 ~/Library/Logs/dwmac.log     # should say "dwmac ready."
```

## Uninstall

```sh
./scripts/uninstall.sh
```

This removes the binary and the LaunchAgent plist. Your config file at
`~/.config/dwmac/config.json` and the log file at
`~/Library/Logs/dwmac.log` are left in place.

## Hotkeys

The default modifier (`Mod`) is **Control + Command**. Configure it in
`config.json` (see below).

| Combo | Action |
|---|---|
| `Mod + [` | Arm **left** slot + open Mission Control. The next focused window slots into left. |
| `Mod + ]` | Arm **right** slot + open Mission Control. |
| `Mod + \` | Arm **center** slot + open Mission Control. |
| `Mod + Return` | Arm fullscreen pick. Press again to exit fullscreen. |
| `Mod + J` / `Mod + K` | Cycle focus across the populated slots. |
| `Mod + R` | Re-tile the active screen. |
| `Mod + T` | Toggle dwmac management on/off for the active screen. |
| `Mod + F` | Toggle floating for the focused window. |
| `Mod + ,` / `Mod + .` | Focus previous / next monitor. |
| `Mod + Shift + ,` / `Mod + Shift + .` | Move focused window to prev / next monitor. |
| `Mod + 1` … `Mod + 9` | Switch the active screen to workspace N. |
| `Mod + Shift + 1` … `Mod + Shift + 9` | Send focused window to workspace N. |
| `Mod + Shift + C` | Close focused window. |
| `Mod + Shift + B` | Dump focused window + running apps to log (for finding bundle IDs). |
| `Mod + Shift + Q` | Quit dwmac (LaunchAgent will not respawn after a clean quit). |

If you don't pick a window within 6 seconds of pressing one of the arming
hotkeys, the arm is dropped automatically.

If you set the modifier to include **Shift**, the `Mod + Shift + …` shortcuts
collapse to the same combo as `Mod + …` and the second registration will be
ignored. Choose a modifier that doesn't already include Shift for the full set.

## Configuration

`~/.config/dwmac/config.json` is created from defaults on first launch.

```json
{
  "modifier": ["control", "command"],
  "centerFraction": 0.50,
  "sideFraction": 0.33,
  "outerGap": 8,
  "innerGap": 6,
  "workspaceCount": 9,
  "floatBundleIDs": [
    "com.apple.systempreferences",
    "com.apple.systemsettings",
    "com.apple.ScreenSaver.Engine",
    "com.apple.installer",
    "com.apple.calculator",
    "com.apple.PrintCenter",
    "com.apple.archiveutility",
    "com.apple.FontBook",
    "com.apple.audio.AudioMIDISetup",
    "com.apple.Stickies",
    "com.apple.ActivityMonitor",
    "com.apple.ColorSyncUtility",
    "com.apple.DigitalColorMeter",
    "com.apple.PhotoBooth"
  ],
  "ignoreBundleIDs": [],
  "logLevel": "info",
  "wideMinAspectRatio": 2.0
}
```

`centerFraction + 2 × sideFraction` is allowed to exceed 1.0 — the overlap is
what gives the focused center its visual cover over the side panes' inner
edges. Modifier tokens are any combination of `control`, `command`, `option`,
`shift`. Reload after edits:

```sh
launchctl kickstart -k gui/$(id -u)/com.dwmac.agent
```

## Excluding apps

* `ignoreBundleIDs` — never managed at all.
* `floatBundleIDs` — tracked but never moved or resized.

To find a bundle ID, focus the window and press `Mod + Shift + B`. The log line
`FOCUSED: pid=… bundle=… title=…` shows the identifier. The defaults already
cover the common offenders (System Settings, Calculator, Installer, etc.).

Additionally the tiler automatically floats any window that is:

* a dialog / sheet / floating subrole
* `kAXModalAttribute = true` (modal "Save changes?" panels)
* smaller than 200 × 200 px
* not resizable (`kAXSizeAttribute` is not settable)
* missing a close button (transient popovers and pickers)

## Workspaces

dwmac has nine virtual workspaces per screen, orthogonal to macOS Spaces.
Switching workspaces parks every window of the old workspace off-canvas and
un-parks the new workspace's windows. macOS Spaces are not touched.

## Troubleshooting

```sh
# Is the agent running?
launchctl print gui/$(id -u)/com.dwmac.agent | grep -E 'state|last exit'
# state = running         → all good
# last exit code = 78     → Accessibility permission not granted

# Live log
tail -f ~/Library/Logs/dwmac.log

# Reload after config change
launchctl kickstart -k gui/$(id -u)/com.dwmac.agent

# Permanent stop (until next install.sh)
launchctl bootout gui/$(id -u)/com.dwmac.agent

# Verify the binary's code signature
codesign -dv ~/.local/bin/dwmac
codesign -d --requirements - ~/.local/bin/dwmac
```

If the agent keeps exiting with code 78 even though the System Settings
toggle is on, the existing TCC entry is bound to an old cdhash. Remove
the row in System Settings (select → `−`), then `+` it back via
`Cmd + Shift + G` → `/Users/<you>/.local/bin/dwmac`. With the signed
binary in place the new grant will persist across rebuilds.

## Development

```sh
swift build               # debug
swift build -c release    # release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Component layout:

```
Sources/dwmac/
├── main.swift                      bootstrap + RunLoop
├── Engine.swift                    event handling, tiling, commands
├── Config/                         JSON config + defaults
├── Permissions/Accessibility.swift AX trust check + instructions
├── Hotkeys/                        Carbon RegisterEventHotKey wrapper
├── Windows/                        AX adapter + observer + store
├── Layout/                         three-pane math + screen state
├── Workspaces/                     park position helper
├── Commands/                       hotkey → engine action map
└── Util/                           file logger + geometry helpers
```

## License

[MIT](LICENSE).

## Acknowledgments

Inspired by [dwm](https://dwm.suckless.org/). The dwmac design departs from
the classic master/stack layout: instead of one master plus two side stacks
of many windows each, it picks three fixed single-window slots and treats
everything else as a hidden pool the user pulls into a slot on demand.
