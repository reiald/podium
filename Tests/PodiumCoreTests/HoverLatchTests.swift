import CoreGraphics
import Foundation
import Testing
@testable import PodiumCore

@Suite struct HoverLatchTests {
    let a = StripSlot(stageID: UUID(), frame: CGRect(x: 0, y: 0, width: 100, height: 100), tiltRadians: 0)
    let b = StripSlot(stageID: UUID(), frame: CGRect(x: 0, y: 105, width: 100, height: 100), tiltRadians: 0)

    @Test func hoverLatchesAcrossGapBetweenSlots() {
        var l = HoverLatch()
        l.update(pointer: CGPoint(x: 50, y: 50), slots: [a, b])
        #expect(l.hovered == a.stageID)
        // In the gap (y 100..105): inside a's 10-pt margin, so it stays on a.
        l.update(pointer: CGPoint(x: 50, y: 102), slots: [a, b])
        #expect(l.hovered == a.stageID)
        // Inside b's own frame, but also within a's margin: still latched.
        l.update(pointer: CGPoint(x: 50, y: 107), slots: [a, b])
        #expect(l.hovered == a.stageID)
        // Past a's margin, inside b: switch.
        l.update(pointer: CGPoint(x: 50, y: 120), slots: [a, b])
        #expect(l.hovered == b.stageID)
    }

    @Test func hoverClearsWhenPointerNil() {
        var l = HoverLatch()
        l.update(pointer: CGPoint(x: 50, y: 50), slots: [a, b])
        l.update(pointer: nil, slots: [a, b])
        #expect(l.hovered == nil)
    }

    @Test func hoverClearsWhenPointerLeavesAllSlots() {
        var l = HoverLatch()
        l.update(pointer: CGPoint(x: 50, y: 50), slots: [a, b])
        l.update(pointer: CGPoint(x: 500, y: 500), slots: [a, b])
        #expect(l.hovered == nil)
    }

    @Test func hoverClearsWhenSlotRemoved() {
        var l = HoverLatch()
        l.update(pointer: CGPoint(x: 50, y: 50), slots: [a, b])
        l.update(pointer: CGPoint(x: 50, y: 52), slots: [b])
        #expect(l.hovered == nil)
    }
}
