#if canImport(XCTest)
import XCTest
@testable import dwmac

final class LayoutTests: XCTestCase {

    private let params = Layout.Params(leftFraction: 0.33,
                                       centerFraction: 0.50,
                                       rightFraction: 0.33,
                                       outerGap: 8)

    func testZonesBasic() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let plan = Layout.compute(axVisibleFrame: vf, params: params)

        // Usable = 984 wide after outer gap.
        // Side width = floor(984 * 0.33) = 324
        // Center width = floor(984 * 0.50) = 492
        // Center x = floor((984 - 492)/2) + 8 = 246 + 8 = 254
        XCTAssertEqual(plan.leftZone,
                       CGRect(x: 8, y: 8, width: 324, height: 784))
        XCTAssertEqual(plan.centerZone,
                       CGRect(x: 254, y: 8, width: 492, height: 784))
        XCTAssertEqual(plan.rightZone,
                       CGRect(x: 8 + 984 - 324, y: 8, width: 324, height: 784))
    }

    func testSidesAnchorToOuterEdges() {
        let vf = CGRect(x: 100, y: 50, width: 1200, height: 900)
        let plan = Layout.compute(axVisibleFrame: vf, params: params)
        XCTAssertEqual(plan.leftZone.minX, 108)  // vf.minX + outerGap
        XCTAssertEqual(plan.rightZone.maxX, 1292) // vf.maxX - outerGap
    }

    func testCenterIsCentered() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let plan = Layout.compute(axVisibleFrame: vf, params: params)
        // The center pane's center X should equal vf's center X.
        let vfCenterX = vf.midX
        let centerMid = plan.centerZone.midX
        XCTAssertEqual(centerMid, vfCenterX, accuracy: 1.0)
    }

    func testSlotPlace() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        let b = WindowID(value: 2)
        XCTAssertNil(slots.place(a, in: .center))
        XCTAssertEqual(slots.center, a)
        let displaced = slots.place(b, in: .center)
        XCTAssertEqual(displaced, a)
        XCTAssertEqual(slots.center, b)
        XCTAssertTrue(slots.hiddenPool.contains(a))
    }

    func testSlotRemove() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        slots.place(a, in: .left)
        slots.remove(a)
        XCTAssertNil(slots.left)
        XCTAssertFalse(slots.hiddenPool.contains(a))
    }

    func testSlotPlaceMovesAcross() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        slots.place(a, in: .left)
        let displaced = slots.place(a, in: .center)
        XCTAssertNil(displaced)               // moving the same id should not displace anything
        XCTAssertNil(slots.left)
        XCTAssertEqual(slots.center, a)
        XCTAssertFalse(slots.hiddenPool.contains(a))
    }

    /// Regression: placing a window into the slot it already occupies must
    /// not duplicate it into the hidden pool. Without the guard, the
    /// arming flow would end up tracking the same window in both
    /// `slots[slot]` and `hiddenPool`, and the next tile would
    /// (incorrectly) treat it as a pool window too.
    func testSlotPlaceWhenAlreadyInSlot() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        slots.place(a, in: .left)
        let displaced = slots.place(a, in: .left)
        XCTAssertNil(displaced)
        XCTAssertEqual(slots.left, a)
        XCTAssertFalse(slots.hiddenPool.contains(a))
        XCTAssertNil(slots.center)
        XCTAssertNil(slots.right)
    }

    func testFractionsClamped() {
        var c = Config.default
        c.centerFraction = 0.9
        c.leftFraction = 0.8
        c.rightFraction = 0.8
        c = c.validated()
        XCTAssertLessThanOrEqual(c.centerFraction, 0.80)
        XCTAssertLessThanOrEqual(c.leftFraction, 0.60)
        XCTAssertLessThanOrEqual(c.rightFraction, 0.60)
    }

    /// Per-side fractions produce independent widths.
    func testAsymmetricSides() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let p = Layout.Params(leftFraction: 0.20,
                              centerFraction: 0.50,
                              rightFraction: 0.40,
                              outerGap: 8)
        let plan = Layout.compute(axVisibleFrame: vf, params: p)
        // usable.width = 984. left = floor(984*0.2) = 196. right = floor(984*0.4) = 393.
        XCTAssertEqual(plan.leftZone.width, 196)
        XCTAssertEqual(plan.rightZone.width, 393)
        XCTAssertEqual(plan.leftZone.minX, 8)
        XCTAssertEqual(plan.rightZone.maxX, 992)
    }

    func testFloatsTrackSeparately() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        slots.floats.append(a)
        XCTAssertFalse(slots.slotted.contains(a))
        XCTAssertTrue(slots.allIDs.contains(a))
    }

    func testSlotForPoint_centerWins() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let plan = Layout.compute(axVisibleFrame: vf, params: params)
        let p = CGPoint(x: 500, y: 400)
        XCTAssertEqual(SlotLayout.slotForPoint(p, plan: plan), .center)
    }

    func testSlotForPoint_leftWins() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let plan = Layout.compute(axVisibleFrame: vf, params: params)
        let p = CGPoint(x: 100, y: 400)
        XCTAssertEqual(SlotLayout.slotForPoint(p, plan: plan), .left)
    }

    func testSlotForPoint_rightWins() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let plan = Layout.compute(axVisibleFrame: vf, params: params)
        let p = CGPoint(x: 900, y: 400)
        XCTAssertEqual(SlotLayout.slotForPoint(p, plan: plan), .right)
    }

    func testFullscreenIncludedInAllIDs() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        slots.fullscreen = a
        XCTAssertTrue(slots.slotted.contains(a))
        XCTAssertTrue(slots.allIDs.contains(a))
    }

    func testRemoveClearsFullscreen() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        slots.fullscreen = a
        slots.remove(a)
        XCTAssertNil(slots.fullscreen)
    }

    /// Drag from one occupied slot to another → swap. The previous occupant
    /// of the target moves to the dragged window's old slot, not the pool.
    func testMoveOrSwap_slotToSlot_swaps() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        let b = WindowID(value: 2)
        slots.place(a, in: .left)
        slots.place(b, in: .right)
        slots.moveOrSwap(a, into: .right)
        XCTAssertEqual(slots.right, a)
        XCTAssertEqual(slots.left, b)
        XCTAssertTrue(slots.hiddenPool.isEmpty)
    }

    /// Drag from an occupied slot to an empty slot → move (target's
    /// previous occupant is nil, so the source slot becomes empty).
    func testMoveOrSwap_slotToEmpty_moves() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        slots.place(a, in: .left)
        slots.moveOrSwap(a, into: .center)
        XCTAssertEqual(slots.center, a)
        XCTAssertNil(slots.left)
        XCTAssertTrue(slots.hiddenPool.isEmpty)
    }

    /// Drag from the hidden pool into a slot → existing slot occupant
    /// displaces into the pool (no swap target exists).
    func testMoveOrSwap_poolToSlot_displacesToPool() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        let b = WindowID(value: 2)
        slots.place(a, in: .left)
        slots.hiddenPool.append(b)
        slots.moveOrSwap(b, into: .left)
        XCTAssertEqual(slots.left, b)
        XCTAssertTrue(slots.hiddenPool.contains(a))
        XCTAssertFalse(slots.hiddenPool.contains(b))
    }

    /// Moving a window into its own slot is a no-op.
    func testMoveOrSwap_sameSlot_noop() {
        var slots = SlotLayout()
        let a = WindowID(value: 1)
        slots.place(a, in: .center)
        slots.moveOrSwap(a, into: .center)
        XCTAssertEqual(slots.center, a)
        XCTAssertTrue(slots.hiddenPool.isEmpty)
    }

    func testWideMinAspectRatioClamp() {
        var c = Config.default
        c.wideMinAspectRatio = 10  // out of range
        c = c.validated()
        XCTAssertLessThanOrEqual(c.wideMinAspectRatio, 6.0)
        XCTAssertGreaterThanOrEqual(c.wideMinAspectRatio, 1.0)
    }
}
#endif
