import Foundation

/// Wires hotkeys to engine actions. Registration is done once at boot;
/// callbacks fire on the main RunLoop because RegisterEventHotKey delivers there.
enum Commands {

    static func registerAll(engine: Engine, config: Config) {
        let mods = carbonMask(from: config.modifier)
        // "Shift-variant" hotkeys (send-to-monitor, send-to-workspace,
        // close, dump, quit) normally use Mod+Shift. But if the
        // configured modifier already includes Shift, Mod+Shift+X
        // collapses to the same combo as Mod+X and the registration
        // gets refused as a duplicate. In that case fall back to
        // Mod+Option for the variant — orthogonal to Mod+X and orthogonal
        // to the configured modifier set.
        let modsShift: UInt32
        if config.modifier.contains(.shift) {
            modsShift = mods | CarbonModifier.option
            Log.info("Mod already includes Shift; shift-variant hotkeys are remapped to Mod+Option")
        } else {
            modsShift = mods | CarbonModifier.shift
        }

        let mgr = HotkeyManager.shared
        mgr.installEventHandler()

        // Cycle focus among the three slots on the active screen.
        mgr.register(keyCode: VKey.j, modifierMask: mods) { engine.cycleFocusedSlot(offset: +1) }
        mgr.register(keyCode: VKey.k, modifierMask: mods) { engine.cycleFocusedSlot(offset: -1) }

        // Arm a slot + open Mission Control. The next focus change populates
        // the slot. If MC misbehaves on this macOS version, use Cmd+Tab or
        // click another window — any focus change within 6 s fills the slot.
        mgr.register(keyCode: VKey.leftBracket,  modifierMask: mods) { engine.armLeftSlot() }
        mgr.register(keyCode: VKey.rightBracket, modifierMask: mods) { engine.armRightSlot() }
        mgr.register(keyCode: VKey.backslash,    modifierMask: mods) { engine.armCenterSlot() }

        // Fullscreen pick: open Mission Control, the next focused window
        // takes the entire visible frame. Pressing again exits fullscreen.
        mgr.register(keyCode: VKey.return,       modifierMask: mods) { engine.armFullscreen() }

        // Reload + re-tile.  Mod+R is the "refresh" key: it re-reads the
        // config file from disk and re-applies the layout to every
        // screen, so a config edit followed by Mod+R is everything
        // needed (no separate retile-only binding).
        mgr.register(keyCode: VKey.r, modifierMask: mods) { engine.reloadConfig() }
        mgr.register(keyCode: VKey.t, modifierMask: mods) { engine.toggleTiling() }
        mgr.register(keyCode: VKey.f, modifierMask: mods) { engine.toggleFloatingFocused() }

        // Focus / send between monitors.
        mgr.register(keyCode: VKey.comma,  modifierMask: mods)      { engine.focusMonitor(offset: -1) }
        mgr.register(keyCode: VKey.period, modifierMask: mods)      { engine.focusMonitor(offset: +1) }
        mgr.register(keyCode: VKey.comma,  modifierMask: modsShift) { engine.sendFocusedToMonitor(offset: -1) }
        mgr.register(keyCode: VKey.period, modifierMask: modsShift) { engine.sendFocusedToMonitor(offset: +1) }

        // Workspaces.
        let count = min(9, max(1, config.workspaceCount))
        for n in 1...count {
            let key = VKey.numbers[n - 1]
            mgr.register(keyCode: key, modifierMask: mods)      { engine.switchToWorkspace(n) }
            mgr.register(keyCode: key, modifierMask: modsShift) { engine.sendFocusedToWorkspace(n) }
        }

        // Misc.
        mgr.register(keyCode: VKey.c, modifierMask: modsShift) { engine.closeFocused() }
        mgr.register(keyCode: VKey.b, modifierMask: modsShift) { engine.dumpDiagnostics() }
        mgr.register(keyCode: VKey.q, modifierMask: modsShift) {
            Log.info("Quit hotkey pressed — exiting.")
            mgr.unregisterAll()
            engine.shutdown()
            exit(0)
        }

        Log.info("registered hotkeys with modifier mask 0x\(String(mods, radix: 16))")
    }
}
