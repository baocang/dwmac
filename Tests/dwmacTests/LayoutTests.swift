#if canImport(XCTest)
import XCTest
@testable import dwmac

final class LayoutTests: XCTestCase {

    private let params = Layout.Params(centerFraction: 0.50,
                                       sideFraction: 0.33,
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
        c.sideFraction = 0.8
        c = c.validated()
        XCTAssertLessThanOrEqual(c.centerFraction, 0.80)
        XCTAssertLessThanOrEqual(c.sideFraction, 0.50)
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
}
#endif
