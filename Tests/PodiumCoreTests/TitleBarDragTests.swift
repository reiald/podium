import CoreGraphics
import Testing
@testable import PodiumCore

private let a = WindowRef(pid: 1, windowID: 10)
private let b = WindowRef(pid: 1, windowID: 20)
private let frameA = CGRect(x: 100, y: 100, width: 800, height: 600)
private let frameB = CGRect(x: 0, y: 30, width: 3000, height: 1500)
private let band = CGRect(x: 2700, y: 0, width: 300, height: 1692)

@Test func titleBarDragOfOneWindowIsADragOut() {
    let moved = titleBarDragged(
        before: [a: frameA, b: frameB],
        after: [a: frameA.offsetBy(dx: 2400, dy: 40), b: frameB],
        pressedAt: CGPoint(x: 400, y: 110), releasedAt: CGPoint(x: 2800, y: 150), band: band)
    #expect(moved?.0 == a)
    #expect(moved?.1 == frameA)
}

/// Teams settling its own window during a click elsewhere: it moved, but not with the pointer.
@Test func windowThatMovedByItselfIsNotADragOut() {
    let moved = titleBarDragged(
        before: [a: frameA, b: frameB],
        after: [a: frameA, b: frameB.offsetBy(dx: 0, dy: 8)],
        pressedAt: CGPoint(x: 2900, y: 700), releasedAt: CGPoint(x: 2900, y: 700), band: band)
    #expect(moved == nil)
}

@Test func pressOutsideTheMovedWindowIsNotADragOut() {
    let moved = titleBarDragged(
        before: [a: frameA],
        after: [a: frameA.offsetBy(dx: 800, dy: 0)],
        pressedAt: CGPoint(x: 2000, y: 50), releasedAt: CGPoint(x: 2800, y: 50), band: band)
    #expect(moved == nil)
}

@Test func resizeIsNotADragOut() {
    let moved = titleBarDragged(
        before: [a: frameA],
        after: [a: CGRect(x: 400, y: 100, width: 500, height: 600)],
        pressedAt: CGPoint(x: 101, y: 400), releasedAt: CGPoint(x: 2801, y: 400), band: band)
    #expect(moved == nil)
}

/// An app may clamp the window short of the pointer (the menu bar, a screen edge).
@Test func dragClampedByTheAppStillCounts() {
    let moved = titleBarDragged(
        before: [a: frameA],
        after: [a: frameA.offsetBy(dx: 2400, dy: -70)],
        pressedAt: CGPoint(x: 400, y: 110), releasedAt: CGPoint(x: 2800, y: 0), band: band)
    #expect(moved?.0 == a)
}

/// A click on a wide window's title bar where it reaches into the strip band, moving it a
/// little: the press began in the band, so the window was never dragged into it.
@Test func pressThatBeganInTheBandIsNotADragOut() {
    let moved = titleBarDragged(
        before: [b: frameB],
        after: [b: frameB.offsetBy(dx: 6, dy: 2)],
        pressedAt: CGPoint(x: 2800, y: 40), releasedAt: CGPoint(x: 2806, y: 42), band: band)
    #expect(moved == nil)
}
