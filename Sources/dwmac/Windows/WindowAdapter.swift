import ApplicationServices
import Cocoa
import Foundation

/// A unique identifier for a managed window. Stable for the window's lifetime.
struct WindowID: Hashable, CustomStringConvertible {
    let value: UInt64
    var description: String { "win#\(value)" }
}

/// Wraps an AX window element with cached pid and a generated WindowID.
final class WindowAdapter: Hashable {
    let id: WindowID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?

    init(id: WindowID, element: AXUIElement, pid: pid_t, bundleID: String?) {
        self.id = id
        self.element = element
        self.pid = pid
        self.bundleID = bundleID
    }

    // MARK: - Equatable / Hashable
    static func == (lhs: WindowAdapter, rhs: WindowAdapter) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Geometry

    func getFrame() -> CGRect? {
        guard let pos = readPoint(kAXPositionAttribute as CFString),
              let size = readSize(kAXSizeAttribute as CFString)
        else { return nil }
        return CGRect(origin: pos, size: size)
    }

    @discardableResult
    func setFrame(_ rect: CGRect) -> Bool {
        let snapped = Geometry.floored(rect)
        let posOK  = writePoint(kAXPositionAttribute as CFString, snapped.origin)
        let sizeOK = writeSize(kAXSizeAttribute as CFString, snapped.size)
        // Re-apply position because some apps adjust position after a size change.
        _ = writePoint(kAXPositionAttribute as CFString, snapped.origin)
        return posOK && sizeOK
    }

    // MARK: - Focus / close / raise

    /// Bring the window to the front and focus it.
    @discardableResult
    func focus() -> Bool {
        var raiseOK = false
        let raiseStatus = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        raiseOK = (raiseStatus == .success)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        // Activate the owning app, otherwise raise on an unfocused app is a no-op.
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [])
        }
        return raiseOK
    }

    @discardableResult
    func close() -> Bool {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &ref)
        guard status == .success, let value = ref else { return false }
        let closeBtn = value as! AXUIElement
        let press = AXUIElementPerformAction(closeBtn, kAXPressAction as CFString)
        return press == .success
    }

    // MARK: - Metadata

    var role: String?    { copyStringAttribute(kAXRoleAttribute as CFString) }
    var subrole: String? { copyStringAttribute(kAXSubroleAttribute as CFString) }
    var title: String?   { copyStringAttribute(kAXTitleAttribute as CFString) }

    var isMinimized: Bool {
        var ref: CFTypeRef?
        let s = AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &ref)
        guard s == .success, let b = ref as? Bool else { return false }
        return b
    }

    // MARK: - AX helpers

    private func copyStringAttribute(_ attr: CFString) -> String? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attr, &ref)
        guard status == .success, let s = ref as? String else { return nil }
        return s
    }

    private func readPoint(_ attr: CFString) -> CGPoint? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attr, &ref)
        guard status == .success, let value = ref else { return nil }
        var out = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &out) else { return nil }
        return out
    }

    private func readSize(_ attr: CFString) -> CGSize? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attr, &ref)
        guard status == .success, let value = ref else { return nil }
        var out = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &out) else { return nil }
        return out
    }

    @discardableResult
    private func writePoint(_ attr: CFString, _ p: CGPoint) -> Bool {
        var v = p
        guard let axv = AXValueCreate(.cgPoint, &v) else { return false }
        let s = AXUIElementSetAttributeValue(element, attr, axv)
        return s == .success
    }

    @discardableResult
    private func writeSize(_ attr: CFString, _ sz: CGSize) -> Bool {
        var v = sz
        guard let axv = AXValueCreate(.cgSize, &v) else { return false }
        let s = AXUIElementSetAttributeValue(element, attr, axv)
        return s == .success
    }
}

/// Helpers for working with running apps.
enum AppAX {
    /// Returns the application AXUIElement for a pid.
    static func application(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    /// Returns the current AX windows of an application.
    static func windows(of appElement: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &ref)
        guard status == .success, let arr = ref as? [AXUIElement] else { return [] }
        return arr
    }
}
