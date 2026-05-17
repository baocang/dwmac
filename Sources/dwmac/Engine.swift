import ApplicationServices
import Cocoa
import CoreGraphics
import Foundation

/// What kind of pick the user has armed.
enum ArmKind {
    case slot(Slot)
    case fullscreen
}

/// The central coordinator. Owns the window store, screen states, the observer,
/// and all higher-level operations invoked by Commands.
final class Engine {
    let config: Config
    let store = WindowStore()
    let observer = WindowObserver()
    private(set) var screens: [CGDirectDisplayID: ScreenState] = [:]

    /// While non-nil, the next focus change applies the armed action.
    private var armed: (kind: ArmKind, displayID: CGDirectDisplayID, previousFocus: WindowID?)?
    private var armedExpiry: DispatchWorkItem?

    /// Pending user-drag re-slot. Coalesces a burst of move events
    /// into one action when the drag settles.
    private var pendingMoves: [WindowID: DispatchWorkItem] = [:]

    private var suppressionEnd: Date = .distantPast

    init(config: Config) {
        self.config = config
        Log.level = config.logLevel
    }

    // MARK: - Bootstrap

    func bootstrap() {
        rebuildScreens()
        observer.onEvent = { [weak self] ev in self?.handle(ev) }
        observer.start()

        observer.enumerateAllExistingWindows { [weak self] win, pid, bundle in
            self?.handleAppearance(element: win, pid: pid, bundleID: bundle, initial: true)
        }
        tileAll()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.handleScreenReconfigure()
        }
    }

    func shutdown() {
        observer.stop()
    }

    /// Whether the engine should tile on the given screen.
    private func shouldManage(_ screen: NSScreen) -> Bool {
        if !config.manageBuiltin && ScreenSpace.isBuiltin(screen) { return false }
        if config.wideAspectFilter {
            let f = screen.frame
            let ratio = f.width / max(1, f.height)
            if ratio < config.wideMinAspectRatio { return false }
        }
        return true
    }

    private func rebuildScreens() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let id = ScreenSpace.displayID(screen)
            seen.insert(id)
            if let existing = screens[id] {
                existing.tilingEnabled = shouldManage(screen)
            } else {
                screens[id] = ScreenState(displayID: id,
                                          tilingEnabled: shouldManage(screen),
                                          workspaceCount: config.workspaceCount)
            }
        }
        for stale in screens.keys where !seen.contains(stale) {
            screens.removeValue(forKey: stale)
        }
    }

    // MARK: - Event handling

    private func handle(_ event: WindowEvent) {
        switch event {
        case .appeared(let el, let pid, let bid):
            handleAppearance(element: el, pid: pid, bundleID: bid, initial: false)
        case .destroyed(let el, _):
            if let id = store.remove(element: el) {
                removeFromAnySlot(id)
                tileAll()
            }
        case .movedOrResized(let el, _):
            if Date() < suppressionEnd { return }
            if let id = store.id(for: el) {
                schedulePendingMove(id)
            }
        case .minimized(let el, _):
            if let id = store.id(for: el) {
                removeFromAnySlot(id)
                tileAll()
            }
        case .demined(let el, let pid):
            handleAppearance(element: el, pid: pid, bundleID: nil, initial: false)
        case .appQuit(let pid):
            let removed = store.removeAll(pid: pid)
            for id in removed { removeFromAnySlot(id) }
            tileAll()
        case .focusedWindowChanged:
            handleFocusChanged()
        }
    }

    private func handleScreenReconfigure() {
        rebuildScreens()
        for (id, adapter) in store.adapters {
            guard let frame = adapter.getFrame() else { continue }
            guard let screen = ScreenSpace.screenContaining(axPoint: Geometry.center(frame)) else { continue }
            let newIdx = newIndex(for: ScreenSpace.displayID(screen))
            store.mutateState(id) { $0.screenIndex = newIdx }
        }
        tileAll()
    }

    private func newIndex(for displayID: CGDirectDisplayID) -> Int {
        NSScreen.screens.firstIndex(where: { ScreenSpace.displayID($0) == displayID }) ?? 0
    }

    // MARK: - Window appearance / placement

    private func handleAppearance(element: AXUIElement, pid: pid_t, bundleID: String?, initial: Bool) {
        guard isManageable(element: element, pid: pid, bundleID: bundleID) else { return }
        let probe = WindowAdapter(id: WindowID(value: 0), element: element, pid: pid, bundleID: bundleID)
        guard let frame = probe.getFrame() else { return }
        guard let screen = ScreenSpace.screenContaining(axPoint: Geometry.center(frame)) else { return }
        let display = ScreenSpace.displayID(screen)
        let screenIndex = newIndex(for: display)

        let screenState = screens[display] ?? {
            let s = ScreenState(displayID: display,
                                tilingEnabled: shouldManage(screen),
                                workspaceCount: config.workspaceCount)
            screens[display] = s
            return s
        }()
        let workspace = screenState.currentWorkspace
        let isFloat = shouldFloatByDefault(bundleID: bundleID, frame: frame, element: element)

        guard let id = store.add(element: element,
                                 pid: pid,
                                 bundleID: bundleID,
                                 screenIndex: screenIndex,
                                 workspace: workspace,
                                 isFloating: isFloat) else { return }

        if isFloat {
            screenState.mutateSlots(workspace) { $0.floats.append(id) }
        } else if screenState.tilingEnabled {
            placeIntoSlot(id: id, screenState: screenState, workspace: workspace)
        } else {
            // Unmanaged screen — track in the hidden pool but don't move.
            screenState.mutateSlots(workspace) { $0.hiddenPool.append(id) }
        }
        if !initial { tile(screenState: screenState) }
    }

    private func isManageable(element: AXUIElement, pid: pid_t, bundleID: String?) -> Bool {
        if let bid = bundleID, config.ignoreBundleIDs.contains(bid) { return false }
        var roleVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal)
        let role = roleVal as? String
        // Only honest top-level windows. Skip menus, sheets, popovers,
        // tooltips, drawers etc. that some apps surface in AXWindows.
        guard role == kAXWindowRole as String else { return false }
        return true
    }

    /// Bundle IDs and subroles that we cannot reliably tile (transient menus,
    /// dropdowns, picker UIs).  These come from third-party apps that surface
    /// auxiliary UI elements as separate AXWindows.
    private static let neverTileSubroles: Set<String> = [
        kAXDialogSubrole as String,
        kAXSystemDialogSubrole as String,
        kAXFloatingWindowSubrole as String,
        kAXSystemFloatingWindowSubrole as String,
        "AXSheet",
        "AXUnknown"   // many transient pickers report "AXUnknown"
    ]

    private func shouldFloatByDefault(bundleID: String?, frame: CGRect, element: AXUIElement) -> Bool {
        if let bid = bundleID, config.floatBundleIDs.contains(bid) { return true }
        // Anything smaller than 200x200 is almost certainly a popup.
        if frame.width < 200 || frame.height < 200 { return true }

        // Subrole-based skip list.
        var subVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subVal)
        if let sub = subVal as? String, Engine.neverTileSubroles.contains(sub) { return true }

        // Modal windows — sheets, "Save changes?" dialogs etc.
        var modalVal: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXModalAttribute as CFString, &modalVal)
        if let modal = modalVal as? Bool, modal { return true }

        // Windows the app refuses to resize — fixed-size pickers, small panels.
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable)
        if !settable.boolValue { return true }

        // Windows without a title bar are typically transient (menus, popovers
        // disguised as windows). Probe by asking for the title attribute and
        // treating a missing/empty value combined with no close button as a
        // popup.
        var closeButton: CFTypeRef?
        let closeStatus = AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &closeButton)
        if closeStatus != .success {
            // No close button — almost certainly not a normal window.
            return true
        }

        return false
    }

    /// First available slot order: center → left → right → hidden pool.
    private func placeIntoSlot(id: WindowID, screenState: ScreenState, workspace: Int) {
        screenState.mutateSlots(workspace) { slots in
            if slots.center == nil { slots.center = id; return }
            if slots.left   == nil { slots.left   = id; return }
            if slots.right  == nil { slots.right  = id; return }
            slots.hiddenPool.append(id)
        }
    }

    // MARK: - Tiling

    func tileAll() {
        for s in screens.values { tile(screenState: s) }
    }

    func tile(screenOwning id: WindowID) {
        guard let st = store.state(id) else { return }
        guard let screen = NSScreen.screens[safe: st.screenIndex] else { return }
        let display = ScreenSpace.displayID(screen)
        guard let s = screens[display] else { return }
        tile(screenState: s)
    }

    /// Compute and apply the three-pane layout for one screen.
    func tile(screenState s: ScreenState) {
        guard let screen = NSScreen.screens.first(where: { ScreenSpace.displayID($0) == s.displayID }) else { return }

        // Park off-workspace windows for screens we manage.
        if s.tilingEnabled {
            for (ws, slots) in s.slotsByWorkspace where ws != s.currentWorkspace {
                for id in slots.allIDs { park(id: id) }
            }
        }

        guard s.tilingEnabled else { return }

        let vf = ScreenSpace.axVisibleFrame(screen)

        // Fullscreen short-circuit: park everything except the fullscreen window.
        if let fs = s.currentSlots.fullscreen {
            beginSuppressionWindow()
            // Apply the fullscreen window to the full visible frame.
            if let a = store.adapter(fs) {
                a.setFrame(vf)
                store.mutateState(fs) { $0.lastTiledFrame = vf }
            }
            // Park the rest.
            let slots = s.currentSlots
            for id in [slots.left, slots.center, slots.right].compactMap({ $0 }) where id != fs {
                park(id: id)
            }
            for id in slots.hiddenPool where id != fs { park(id: id) }
            store.adapter(fs)?.focus()
            return
        }

        // Auto-fill empty slots from the hidden pool (FIFO).
        refillEmptySlots(state: s)

        let params = Layout.Params(centerFraction: config.centerFraction,
                                   sideFraction:   config.sideFraction,
                                   outerGap:       config.outerGap)
        let plan = Layout.compute(axVisibleFrame: vf, params: params)

        beginSuppressionWindow()

        let slots = s.currentSlots
        // Hidden-pool windows sit at the center zone, behind the slot windows
        // (z-order is handled by app activation: the focused slot's app is
        // frontmost, so pool windows from other apps are naturally below).
        // This keeps them out of sight without parking off-screen (where some
        // apps clamp positive and leave visible slivers).
        for id in slots.hiddenPool {
            applySlot(id, to: plan.centerZone, anchor: .center)
        }

        // Visible slot windows.
        applySlot(slots.left,   to: plan.leftZone,   anchor: .left)
        applySlot(slots.center, to: plan.centerZone, anchor: .center)
        applySlot(slots.right,  to: plan.rightZone,  anchor: .right)

        // Raise the currently focused window so its app becomes frontmost
        // and the focused slot covers the pool windows behind it.
        if let fid = focusedWindowID(), let a = store.adapter(fid) {
            a.focus()
        }
    }

    /// Pull windows out of the hidden pool to fill empty slots, in order center → left → right.
    private func refillEmptySlots(state s: ScreenState) {
        let ws = s.currentWorkspace
        s.mutateSlots(ws) { slots in
            let order: [Slot] = [.center, .left, .right]
            for slot in order where slots[slot] == nil {
                guard !slots.hiddenPool.isEmpty else { return }
                let id = slots.hiddenPool.removeFirst()
                slots[slot] = id
            }
        }
    }

    private enum SlotAnchor { case left, center, right }

    /// Apply the slot rect, then read back what the app actually accepted and
    /// re-anchor it to the slot's outer edge. Apps with hard minimum sizes
    /// (iTerm2's grid, Xcode's editor, etc.) often refuse our size and shift
    /// themselves to keep their old "center", sliding mostly off-screen.
    /// Edge-anchoring keeps the window's visible side stuck to the screen.
    private func applySlot(_ id: WindowID?, to rect: CGRect, anchor: SlotAnchor) {
        guard let id, let a = store.adapter(id) else { return }
        a.setFrame(rect)
        // Read back the actual frame.
        guard let actual = a.getFrame() else {
            store.mutateState(id) { $0.lastTiledFrame = rect }
            return
        }
        // Compute the X position that pins the window's visible edge to the
        // slot's outer edge regardless of how the app may have stretched.
        let anchoredX: CGFloat
        switch anchor {
        case .left:   anchoredX = rect.minX
        case .right:  anchoredX = rect.maxX - actual.width
        case .center: anchoredX = rect.midX - actual.width / 2
        }
        // Only re-write if the app drifted by more than a pixel.
        if abs(actual.minX - anchoredX) > 1 || abs(actual.minY - rect.minY) > 1 {
            let anchored = CGRect(x: anchoredX,
                                  y: rect.minY,
                                  width: actual.width,
                                  height: actual.height)
            a.setFrame(anchored)
            store.mutateState(id) { $0.lastTiledFrame = anchored }
            Log.debug("slot anchor: id=\(id) target=\(rect) actual=\(actual) anchored=\(anchored)")
        } else {
            store.mutateState(id) { $0.lastTiledFrame = rect }
        }
    }

    private func park(id: WindowID) {
        guard let adapter = store.adapter(id) else { return }
        guard let frame = adapter.getFrame() else { return }
        beginSuppressionWindow()
        adapter.setFrame(Park.parkedFrame(originalSize: frame.size))
    }

    private func beginSuppressionWindow() {
        suppressionEnd = Date().addingTimeInterval(0.4)
    }

    // MARK: - Slot editing helpers

    private func removeFromAnySlot(_ id: WindowID) {
        for state in screens.values {
            for ws in state.slotsByWorkspace.keys {
                state.mutateSlots(ws) { $0.remove(id) }
            }
        }
    }

    // MARK: - Focus tracking

    func focusedWindowID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appEl = AppAX.application(pid: pid)
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &ref)
        guard status == .success, let val = ref else { return nil }
        let element = val as! AXUIElement
        return store.id(for: element)
    }

    func screenState(for id: WindowID) -> ScreenState? {
        guard let s = store.state(id),
              let screen = NSScreen.screens[safe: s.screenIndex] else { return nil }
        return screens[ScreenSpace.displayID(screen)]
    }

    func activeScreenState() -> ScreenState? {
        if let id = focusedWindowID(), let s = screenState(for: id) { return s }
        let mouseAX = mouseAXPoint()
        if let screen = ScreenSpace.screenContaining(axPoint: mouseAX) {
            return screens[ScreenSpace.displayID(screen)]
        }
        return screens.values.first
    }

    private func mouseAXPoint() -> CGPoint {
        let ns = NSEvent.mouseLocation
        let primaryH = ScreenSpace.primaryHeight
        return CGPoint(x: ns.x, y: primaryH - ns.y)
    }

    // MARK: - Focus handler (arming + auto-promote + re-raise)

    private func handleFocusChanged() {
        guard let newFocus = focusedWindowID() else { return }
        guard let st = store.state(newFocus) else { return }
        guard let screen = NSScreen.screens[safe: st.screenIndex] else { return }
        let display = ScreenSpace.displayID(screen)
        guard let screenState = screens[display] else { return }

        // 1. If an arming is pending and the focus actually moved, apply it.
        if let pending = armed,
           newFocus != pending.previousFocus,
           display == pending.displayID,
           screenState.tilingEnabled {
            applyArmedTarget(pending.kind, to: newFocus, on: screenState)
            disarm()
            return
        }

        // 2. No arming: if the new focus is in this screen's hidden pool,
        //    promote it to center (displacing whatever's there to the pool).
        guard screenState.tilingEnabled else { return }
        let ws = screenState.currentWorkspace
        let slots = screenState.slots(ws)
        if slots.fullscreen == nil, slots.hiddenPool.contains(newFocus) {
            screenState.mutateSlots(ws) { s in
                s.hiddenPool.removeAll { $0 == newFocus }
                if let displaced = s.center, displaced != newFocus {
                    s.hiddenPool.append(displaced)
                }
                s.center = newFocus
            }
        }

        // 3. Always retile so z-order matches the focused window.
        tile(screenState: screenState)
    }

    private func applyArmedTarget(_ kind: ArmKind, to id: WindowID, on s: ScreenState) {
        let ws = s.currentWorkspace
        s.mutateSlots(ws) { slots in
            switch kind {
            case .slot(let slot):
                slots.fullscreen = nil
                slots.place(id, in: slot)
            case .fullscreen:
                slots.remove(id)
                slots.fullscreen = id
            }
        }
        tile(screenState: s)
        store.adapter(id)?.focus()
    }

    private func armTarget(_ kind: ArmKind) {
        guard let s = activeScreenState() else { return }
        guard s.tilingEnabled else {
            Log.info("arm: active screen is unmanaged (built-in or filtered) — ignoring")
            return
        }
        let previous = focusedWindowID()
        armed = (kind, s.displayID, previous)
        Log.info("armed \(kind) on display=\(s.displayID); opening Mission Control")
        openMissionControl()

        let work = DispatchWorkItem { [weak self] in
            if self?.armed != nil {
                Log.info("arm timeout — disarming")
                self?.disarm()
            }
        }
        armedExpiry?.cancel()
        armedExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: work)
    }

    private func disarm() {
        armed = nil
        armedExpiry?.cancel()
        armedExpiry = nil
    }

    private func openMissionControl() {
        let path = "/System/Applications/Mission Control.app"
        let url = URL(fileURLWithPath: path)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
            if let error {
                Log.warn("Mission Control open failed: \(error)")
            }
        }
    }

    // MARK: - Commands

    /// Cycle focus among the three populated slots on the active screen.
    func cycleFocusedSlot(offset: Int) {
        guard let s = activeScreenState(), s.tilingEnabled else { return }
        let slots = s.currentSlots
        let order: [WindowID] = Slot.allCases.compactMap { slots[$0] }
        guard !order.isEmpty else { return }
        let cur = focusedWindowID()
        let idx = cur.flatMap(order.firstIndex(of:)) ?? -1
        let next = (idx + offset + order.count * 10) % order.count
        store.adapter(order[next])?.focus()
    }

    func reTile() {
        if let s = activeScreenState() { tile(screenState: s) }
    }

    func toggleTiling() {
        guard let s = activeScreenState() else { return }
        s.tilingEnabled.toggle()
        Log.info("tiling \(s.tilingEnabled ? "on" : "off") for display \(s.displayID)")
        if s.tilingEnabled { tile(screenState: s) }
    }

    func toggleFloatingFocused() {
        guard let s = activeScreenState(), s.tilingEnabled else { return }
        guard let id = focusedWindowID() else { return }
        let ws = s.currentWorkspace
        s.mutateSlots(ws) { slots in
            if slots.floats.contains(id) {
                slots.floats.removeAll { $0 == id }
                if slots.center == nil { slots.center = id }
                else if slots.left == nil { slots.left = id }
                else if slots.right == nil { slots.right = id }
                else { slots.hiddenPool.append(id) }
            } else {
                slots.remove(id)
                slots.floats.append(id)
            }
        }
        tile(screenState: s)
    }

    func focusMonitor(offset: Int) {
        let screensList = NSScreen.screens
        guard !screensList.isEmpty else { return }
        let active = activeScreenState()
        let currentIdx = screensList.firstIndex(where: {
            ScreenSpace.displayID($0) == (active?.displayID ?? 0)
        }) ?? 0
        let nextIdx = (currentIdx + offset + screensList.count * 10) % screensList.count
        let target = screensList[nextIdx]
        let display = ScreenSpace.displayID(target)
        guard let s = screens[display] else { return }
        let slots = s.currentSlots
        if let c = slots.center, let a = store.adapter(c) {
            a.focus()
        } else if let any = (slots.left ?? slots.right ?? slots.hiddenPool.first), let a = store.adapter(any) {
            a.focus()
        }
    }

    func sendFocusedToMonitor(offset: Int) {
        let screensList = NSScreen.screens
        guard let id = focusedWindowID() else { return }
        guard let st = store.state(id) else { return }
        guard let currentScreen = screensList[safe: st.screenIndex] else { return }
        let currentDisplay = ScreenSpace.displayID(currentScreen)
        guard !screensList.isEmpty else { return }
        let currentIdx = screensList.firstIndex(where: { ScreenSpace.displayID($0) == currentDisplay }) ?? 0
        let targetIdx = (currentIdx + offset + screensList.count * 10) % screensList.count
        guard targetIdx != currentIdx else { return }
        let targetScreen = screensList[targetIdx]
        let targetDisplay = ScreenSpace.displayID(targetScreen)
        guard let targetState = screens[targetDisplay] else { return }
        guard let currentState = screens[currentDisplay] else { return }

        removeFromAnySlot(id)
        store.mutateState(id) { $0.screenIndex = targetIdx; $0.workspace = targetState.currentWorkspace }
        if targetState.tilingEnabled {
            placeIntoSlot(id: id, screenState: targetState, workspace: targetState.currentWorkspace)
        } else {
            targetState.mutateSlots(targetState.currentWorkspace) { $0.hiddenPool.append(id) }
        }
        tile(screenState: currentState)
        tile(screenState: targetState)
        store.adapter(id)?.focus()
    }

    func switchToWorkspace(_ n: Int) {
        guard n >= 1 && n <= config.workspaceCount else { return }
        guard let s = activeScreenState() else { return }
        guard s.currentWorkspace != n else { return }
        s.currentWorkspace = n
        tile(screenState: s)
        if let c = s.currentSlots.center, let a = store.adapter(c) { a.focus() }
    }

    func sendFocusedToWorkspace(_ n: Int) {
        guard n >= 1 && n <= config.workspaceCount else { return }
        guard let s = activeScreenState() else { return }
        guard let id = focusedWindowID() else { return }
        let oldWs = s.currentWorkspace
        guard oldWs != n else { return }
        removeFromAnySlot(id)
        store.mutateState(id) { $0.workspace = n }
        if s.tilingEnabled {
            placeIntoSlot(id: id, screenState: s, workspace: n)
        } else {
            s.mutateSlots(n) { $0.hiddenPool.append(id) }
        }
        tile(screenState: s)
    }

    func closeFocused() {
        guard let id = focusedWindowID(), let a = store.adapter(id) else { return }
        _ = a.close()
    }

    func dumpDiagnostics() {
        if let id = focusedWindowID(), let a = store.adapter(id) {
            let title = a.title ?? "(no title)"
            let bid = a.bundleID ?? "(no bundle id)"
            Log.info("FOCUSED: pid=\(a.pid) bundle=\(bid) title=\(title)")
        } else {
            Log.info("FOCUSED: <none>")
        }
        Log.info("--- screens ---")
        for (id, s) in screens {
            Log.info("  display=\(id) managed=\(s.tilingEnabled) workspace=\(s.currentWorkspace) center=\(String(describing: s.currentSlots.center)) left=\(String(describing: s.currentSlots.left)) right=\(String(describing: s.currentSlots.right)) pool=\(s.currentSlots.hiddenPool.count)")
        }
        Log.info("--- running regular apps ---")
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let bid = app.bundleIdentifier ?? "?"
            let name = app.localizedName ?? "?"
            Log.info("  pid=\(app.processIdentifier) bundle=\(bid) name=\(name)")
        }
        Log.info("--- managed windows ---")
        for (id, a) in store.adapters {
            Log.info("  \(id) pid=\(a.pid) bundle=\(a.bundleID ?? "?") title=\(a.title ?? "?")")
        }
    }

    // MARK: - Hotkey entry points (called by Commands)

    /// Arm the left slot and open Mission Control. Next focused window slots into left.
    func armLeftSlot()   { armTarget(.slot(.left)) }
    /// Arm the right slot and open Mission Control.
    func armRightSlot()  { armTarget(.slot(.right)) }
    /// Arm the center slot and open Mission Control.
    func armCenterSlot() { armTarget(.slot(.center)) }

    /// Toggle fullscreen: if any window is currently fullscreen on the active
    /// screen, exit fullscreen and re-tile. Otherwise arm a fullscreen pick
    /// and open Mission Control.
    func armFullscreen() {
        guard let s = activeScreenState() else { return }
        if s.currentSlots.fullscreen != nil {
            s.mutateSlots(s.currentWorkspace) { $0.fullscreen = nil }
            tile(screenState: s)
            return
        }
        armTarget(.fullscreen)
    }

    // MARK: - User drag handling

    /// Debounce user-drag events: a fresh move resets the timer so we only
    /// re-slot once the drag settles (≈0.3 s of stillness).
    private func schedulePendingMove(_ id: WindowID) {
        pendingMoves[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingMoves.removeValue(forKey: id)
            self?.handleUserMove(id)
        }
        pendingMoves[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Called once a user drag has settled. Re-slots the window by zone and
    /// always re-tiles so slot windows snap back to their slot zone — even
    /// when the user moved within the same zone or dropped a window off-screen.
    private func handleUserMove(_ id: WindowID) {
        guard let adapter = store.adapter(id) else { return }
        guard let frame = adapter.getFrame() else { return }
        let centerPt = Geometry.center(frame)
        guard let newScreen = ScreenSpace.screenContaining(axPoint: centerPt) else { return }
        let newDisplay = ScreenSpace.displayID(newScreen)
        guard let newState = screens[newDisplay] else { return }

        // Figure out which screen the window is currently bound to.
        let st = store.state(id)
        let oldScreenIdx = st?.screenIndex
        let oldScreen = oldScreenIdx.flatMap { NSScreen.screens[safe: $0] }
        let oldDisplay = oldScreen.map { ScreenSpace.displayID($0) }

        // If it crossed to another monitor, update assignment and slot it there.
        if newDisplay != oldDisplay {
            if let od = oldDisplay, let oldState = screens[od] {
                oldState.mutateSlots(oldState.currentWorkspace) { $0.remove(id) }
                tile(screenState: oldState)
            }
            let newIdx = newIndex(for: newDisplay)
            store.mutateState(id) { $0.screenIndex = newIdx; $0.workspace = newState.currentWorkspace }
        }

        guard newState.tilingEnabled else { return }

        let ws = newState.currentWorkspace
        let slots = newState.slots(ws)

        // Skip drags of windows the user is managing themselves.
        if slots.floats.contains(id) { return }

        let vf = ScreenSpace.axVisibleFrame(newScreen)
        let params = Layout.Params(centerFraction: config.centerFraction,
                                   sideFraction:   config.sideFraction,
                                   outerGap:       config.outerGap)
        let plan = Layout.compute(axVisibleFrame: vf, params: params)
        let targetSlot = SlotLayout.slotForPoint(centerPt, plan: plan)

        if slots.fullscreen == id {
            // User dragged the fullscreen window — exit fullscreen and slot it.
            newState.mutateSlots(ws) {
                $0.fullscreen = nil
                $0.place(id, in: targetSlot)
            }
            tile(screenState: newState)
            return
        }

        let currentSlot = slots.slotOf(id)
        if currentSlot != targetSlot || newDisplay != oldDisplay {
            newState.mutateSlots(ws) { $0.place(id, in: targetSlot) }
        }

        // Always re-tile so the window snaps back to its full slot rect,
        // even when the user dragged within the same zone.
        tile(screenState: newState)
    }
}

// MARK: - Array helper

extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
