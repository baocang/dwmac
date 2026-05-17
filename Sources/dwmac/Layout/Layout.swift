import CoreGraphics
import Foundation

/// Per-screen layout mode. Decided at tile time from the screen's properties.
enum LayoutMode: CustomStringConvertible {
    /// Wide screen: left / center / right panes with overlap.
    case threePane
    /// Non-wide screen (built-in or aspect < threshold): every window takes
    /// the full visible frame, centered. Focused window is z-raised on top.
    case monocle

    var description: String {
        switch self {
        case .threePane: return "three-pane"
        case .monocle:   return "monocle"
        }
    }
}

/// Named slot in the three-pane layout.
enum Slot: String, CaseIterable, Codable {
    case left, center, right
}

/// One screen+workspace state in three-pane mode.
struct SlotLayout {
    var left:   WindowID?
    var center: WindowID?
    var right:  WindowID?
    /// If non-nil, this window takes the whole visible frame and every other
    /// window on the screen is parked off-screen.
    var fullscreen: WindowID?
    /// Windows on this screen+workspace that aren't currently in any slot.
    /// They keep their existing frame; the user can pull them into a slot
    /// via the armed-slot hotkeys or by Cmd+Tab (focus auto-promotes).
    var hiddenPool: [WindowID] = []
    /// Floating windows that bypass tiling entirely.
    var floats: [WindowID] = []

    var slotted: [WindowID] {
        [fullscreen, left, center, right].compactMap { $0 }
    }

    /// All ids known to this layout, slot or pool or float.
    var allIDs: [WindowID] {
        slotted + hiddenPool + floats
    }

    /// Replace whatever is in `slot` with `id`. Returns the displaced id, if any.
    /// `id` is removed from any other position it occupied (slot or pool).
    /// If `id` is already in `slot`, this is a no-op.
    @discardableResult
    mutating func place(_ id: WindowID, in slot: Slot) -> WindowID? {
        // Already in the target slot — no-op. Without this guard, the
        // following remove() would clear the slot and we'd then append the
        // window to the pool while also putting it back in the slot,
        // duplicating its identity across two positions.
        if self[slot] == id { return nil }
        let displaced = self[slot]
        remove(id)
        self[slot] = id
        if let d = displaced { hiddenPool.append(d) }
        return displaced
    }

    /// Move `id` into `slot`. If `id` currently occupies a different slot,
    /// SWAP it with whatever's in `slot` (the previous occupant of the
    /// target slot moves to `id`'s old slot). If `id` is in the hidden pool
    /// or unknown, falls back to `place` (which displaces the target's
    /// occupant into the pool).
    mutating func moveOrSwap(_ id: WindowID, into slot: Slot) {
        if self[slot] == id { return }
        if let from = slotOf(id) {
            let other = self[slot]
            self[slot] = id
            self[from] = other
            return
        }
        place(id, in: slot)
    }

    /// Find which slot currently holds `id`, if any.
    func slotOf(_ id: WindowID) -> Slot? {
        for s in Slot.allCases where self[s] == id { return s }
        return nil
    }

    /// Remove `id` from any position (slot, fullscreen, pool, floats). No-op if unknown.
    mutating func remove(_ id: WindowID) {
        for s in Slot.allCases where self[s] == id { self[s] = nil }
        if fullscreen == id { fullscreen = nil }
        hiddenPool.removeAll { $0 == id }
        floats.removeAll { $0 == id }
    }

    /// Closest slot (by horizontal centre) to the given AX point, given the
    /// computed zones for the screen.
    static func slotForPoint(_ p: CGPoint, plan: Layout.Computed) -> Slot {
        let dl = abs(p.x - plan.leftZone.midX)
        let dc = abs(p.x - plan.centerZone.midX)
        let dr = abs(p.x - plan.rightZone.midX)
        if dc <= dl && dc <= dr { return .center }
        if dl <= dr             { return .left }
        return .right
    }

    subscript(slot: Slot) -> WindowID? {
        get {
            switch slot {
            case .left:   return left
            case .center: return center
            case .right:  return right
            }
        }
        set {
            switch slot {
            case .left:   left = newValue
            case .center: center = newValue
            case .right:  right = newValue
            }
        }
    }
}

/// Pure layout math: given the visible-frame and fractions, return the
/// absolute rect for each slot. Side panes anchor to the outer edges;
/// they may overlap the center pane if widths sum to more than one.
enum Layout {
    struct Params {
        var centerFraction: Double
        var sideFraction: Double
        var outerGap: Double
    }

    struct Computed {
        var leftZone: CGRect
        var centerZone: CGRect
        var rightZone: CGRect
    }

    static func compute(axVisibleFrame vf: CGRect, params: Params) -> Computed {
        let outer = params.outerGap
        let usable = CGRect(x: vf.origin.x + outer,
                            y: vf.origin.y + outer,
                            width:  max(0, vf.width  - 2*outer),
                            height: max(0, vf.height - 2*outer))

        let sideW   = floor(usable.width * params.sideFraction)
        let centerW = floor(usable.width * params.centerFraction)
        let centerX = usable.origin.x + floor((usable.width - centerW) / 2)

        let left   = CGRect(x: usable.origin.x,
                            y: usable.origin.y,
                            width: sideW,
                            height: usable.height)
        let center = CGRect(x: centerX,
                            y: usable.origin.y,
                            width: centerW,
                            height: usable.height)
        let right  = CGRect(x: usable.maxX - sideW,
                            y: usable.origin.y,
                            width: sideW,
                            height: usable.height)

        return Computed(leftZone:   Geometry.floored(left),
                        centerZone: Geometry.floored(center),
                        rightZone:  Geometry.floored(right))
    }
}
