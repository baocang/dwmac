import Cocoa
import CoreGraphics
import Foundation

/// Per-screen state: managed flag, current workspace, per-workspace slot map.
final class ScreenState {
    let displayID: CGDirectDisplayID
    /// True if dwmac is allowed to manipulate windows on this screen.
    /// Built-in displays default to false; toggled by the user with `Mod+T`.
    var tilingEnabled: Bool
    var currentWorkspace: Int = 1
    var slotsByWorkspace: [Int: SlotLayout]

    init(displayID: CGDirectDisplayID, tilingEnabled: Bool, workspaceCount: Int) {
        self.displayID = displayID
        self.tilingEnabled = tilingEnabled
        var dict: [Int: SlotLayout] = [:]
        for ws in 1...max(1, workspaceCount) {
            dict[ws] = SlotLayout()
        }
        self.slotsByWorkspace = dict
    }

    var currentSlots: SlotLayout {
        get { slotsByWorkspace[currentWorkspace] ?? SlotLayout() }
        set { slotsByWorkspace[currentWorkspace] = newValue }
    }

    func slots(_ ws: Int) -> SlotLayout {
        slotsByWorkspace[ws] ?? SlotLayout()
    }

    func mutateSlots(_ ws: Int, _ block: (inout SlotLayout) -> Void) {
        var z = slotsByWorkspace[ws] ?? SlotLayout()
        block(&z)
        slotsByWorkspace[ws] = z
    }
}

/// Helpers for converting between NSScreen (bottom-left) and AX (top-left) coords.
enum ScreenSpace {
    /// Height of the primary screen (used as the flip pivot).
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// AX visible-frame for a screen (excludes menu bar + Dock).
    static func axVisibleFrame(_ screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        return CGRect(x: vf.origin.x,
                      y: primaryHeight - vf.origin.y - vf.size.height,
                      width: vf.size.width,
                      height: vf.size.height)
    }

    /// AX (full) frame for a screen.
    static func axFrame(_ screen: NSScreen) -> CGRect {
        let f = screen.frame
        return CGRect(x: f.origin.x,
                      y: primaryHeight - f.origin.y - f.size.height,
                      width: f.size.width,
                      height: f.size.height)
    }

    /// Screen whose AX frame contains the given AX point, falling back to nearest.
    static func screenContaining(axPoint p: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        for s in screens where axFrame(s).contains(p) { return s }
        return screens.min { a, b in
            Geometry.distance2(Geometry.center(axFrame(a)), p)
                < Geometry.distance2(Geometry.center(axFrame(b)), p)
        }
    }

    /// Display ID for a screen.
    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    /// True iff the display is built into the Mac chassis.
    static func isBuiltin(_ screen: NSScreen) -> Bool {
        CGDisplayIsBuiltin(displayID(screen)) != 0
    }
}
