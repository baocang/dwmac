import ApplicationServices
import Cocoa
import Foundation

/// Hashable wrapper around AXUIElement so we can use them as dictionary keys.
final class AXElementBox: Hashable {
    let element: AXUIElement
    init(_ e: AXUIElement) { self.element = e }
    static func == (lhs: AXElementBox, rhs: AXElementBox) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

/// Per-window state held by the store.
struct WindowState {
    var screenIndex: Int          // index into NSScreen.screens at registration time
    var workspace: Int            // 1..workspaceCount
    var isFloating: Bool
    var userFloating: Bool        // user toggled with Mod+F — overrides auto-float
    var lastTiledFrame: CGRect?   // last frame we wrote — used to suppress our own move events
}

/// In-memory registry of all managed windows.
final class WindowStore {
    private(set) var adapters: [WindowID: WindowAdapter] = [:]
    private(set) var states:   [WindowID: WindowState]   = [:]
    private var byElement:     [AXElementBox: WindowID]  = [:]
    private var nextRawID: UInt64 = 1

    var allIDs: [WindowID] { Array(adapters.keys) }

    func id(for element: AXUIElement) -> WindowID? {
        byElement[AXElementBox(element)]
    }

    func adapter(_ id: WindowID) -> WindowAdapter? { adapters[id] }
    func state(_ id: WindowID) -> WindowState?    { states[id] }

    func mutateState(_ id: WindowID, _ block: (inout WindowState) -> Void) {
        guard var s = states[id] else { return }
        block(&s)
        states[id] = s
    }

    /// Add a window. Returns the WindowID, or nil if already known or unmanageable.
    func add(element: AXUIElement, pid: pid_t, bundleID: String?,
             screenIndex: Int, workspace: Int, isFloating: Bool) -> WindowID? {
        let box = AXElementBox(element)
        if let existing = byElement[box] { return existing }
        let id = WindowID(value: nextRawID)
        nextRawID += 1
        let adapter = WindowAdapter(id: id, element: element, pid: pid, bundleID: bundleID)
        adapters[id] = adapter
        states[id] = WindowState(screenIndex: screenIndex,
                                 workspace: workspace,
                                 isFloating: isFloating,
                                 userFloating: false,
                                 lastTiledFrame: nil)
        byElement[box] = id
        return id
    }

    /// Remove a window by element.
    @discardableResult
    func remove(element: AXUIElement) -> WindowID? {
        let box = AXElementBox(element)
        guard let id = byElement.removeValue(forKey: box) else { return nil }
        adapters.removeValue(forKey: id)
        states.removeValue(forKey: id)
        return id
    }

    /// Remove a window by id.
    @discardableResult
    func remove(id: WindowID) -> Bool {
        guard let adapter = adapters.removeValue(forKey: id) else { return false }
        states.removeValue(forKey: id)
        byElement.removeValue(forKey: AXElementBox(adapter.element))
        return true
    }

    /// Remove every window owned by a pid (used on app quit).
    func removeAll(pid: pid_t) -> [WindowID] {
        let victims = adapters.values.filter { $0.pid == pid }.map(\.id)
        for id in victims { remove(id: id) }
        return victims
    }

    /// Wipe the entire store. Used by `Engine.reloadConfig` to do a
    /// clean reset before re-enumerating windows.
    func clearAll() {
        adapters.removeAll()
        states.removeAll()
        byElement.removeAll()
    }
}
