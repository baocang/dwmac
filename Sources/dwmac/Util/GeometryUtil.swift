import CoreGraphics
import Foundation

enum Geometry {
    /// Center point of a CGRect.
    static func center(_ r: CGRect) -> CGPoint {
        CGPoint(x: r.midX, y: r.midY)
    }

    /// Floor a rect's x/y/w/h to integers — pixel-snap.
    static func floored(_ r: CGRect) -> CGRect {
        CGRect(x: floor(r.origin.x),
               y: floor(r.origin.y),
               width: floor(r.size.width),
               height: floor(r.size.height))
    }

    /// Squared euclidean distance between two points.
    static func distance2(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx*dx + dy*dy
    }

    /// Clamp v into [lo, hi].
    static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        min(max(v, lo), hi)
    }
}
