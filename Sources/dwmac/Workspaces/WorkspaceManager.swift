import Cocoa
import CoreGraphics
import Foundation

/// Far-off-screen coordinates used to "park" a window that belongs to a
/// workspace that is not currently visible on its screen.
enum Park {
    /// Returns a parked frame for a window whose original size is `original`.
    static func parkedFrame(originalSize: CGSize) -> CGRect {
        CGRect(x: -100_000, y: -100_000,
               width: max(originalSize.width, 100),
               height: max(originalSize.height, 100))
    }
}
