import Testing
import Foundation
import CoreGraphics
@testable import PodiumCore

/// In-memory window server. Can refuse moves, or clamp windows so they stay on a screen.
private final class FakeBackend: WindowBackend {
    var frames: [WindowRef: CGRect] = [:]
    var refuseMoves: Set<WindowRef> = []
    /// When set, every move is clamped so the window stays fully inside this rect.
    var clampTo: CGRect?
    var onSetOrigin: ((CGPoint, WindowRef) -> Void)?
    /// Windows the window server reports alive even though AX cannot reach them
    /// (another Space, a hung app).
    var unreachableButLive: Set<WindowRef> = []
    var screens: [CGRect] = [display]
    /// Full screen frames; defaults to the visible ones.
    var fullFrames: [CGRect]?
    private(set) var sizeChanges = 0
    private(set) var moves: [(WindowRef, CGPoint)] = []

    func frame(of w: WindowRef) -> CGRect? { frames[w] }

    func setOrigin(_ p: CGPoint, of w: WindowRef) -> Bool {
        onSetOrigin?(p, w)
        moves.append((w, p))
        guard var f = frames[w], !refuseMoves.contains(w) else { return false }
        f.origin = p
        if let c = clampTo {
            f.origin.x = min(max(f.minX, c.minX), c.maxX - f.width)
            f.origin.y = min(max(f.minY, c.minY), c.maxY - f.height)
        }
        frames[w] = f
        return true
    }

    func setSize(_ s: CGSize, of w: WindowRef) -> Bool {
        guard frames[w] != nil, !refuseMoves.contains(w) else { return false }
        frames[w]?.size = s
        sizeChanges += 1
        return true
    }

    func liveWindows() -> Set<WindowRef> { Set(frames.keys).union(unreachableButLive) }
    func visibleScreens() -> [CGRect] { screens }
    func screenFrames() -> [CGRect] { fullFrames ?? screens }
    func bundleID(of pid: Int32) -> String? { "com.example.\(pid)" }
}

private let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
private let a = WindowRef(pid: 1, windowID: 10)
private let b = WindowRef(pid: 2, windowID: 20)
private let frameA = CGRect(x: 100, y: 100, width: 300, height: 200)
private let frameB = CGRect(x: 400, y: 300, width: 500, height: 400)

private func withLedger(_ body: (URL, ParkingLedger) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }
    let url = dir.appendingPathComponent("parked.json")
    try body(dir, ParkingLedger(fileURL: url))
}

private func makeReadOnly(_ dir: URL) throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
}

@Test func parkRecordsBeforeMoving() throws {
    try withLedger { dir, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA]
        var ledgerAtMove: [ParkedEntry]?
        backend.onSetOrigin = { _, _ in if ledgerAtMove == nil { ledgerAtMove = ledger.entries() } }
        let mover = WindowMover(backend: backend, ledger: ledger)

        #expect(mover.park(a, display: display, displayID: 7))
        #expect(ledgerAtMove == [ParkedEntry(window: a, bundleID: "com.example.1", originalFrame: frameA, displayID: 7)])
        #expect(backend.frames[a]?.origin == CGPoint(x: 999, y: 799))
        #expect(mover.isParked(a))
        // Durable: a fresh ledger on the same file sees the entry.
        #expect(ParkingLedger(fileURL: dir.appendingPathComponent("parked.json")).entries().map(\.window) == [a])
    }
}

@Test func parkFailsWhenWindowDoesNotLeaveScreen() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA]
        backend.clampTo = display
        let mover = WindowMover(backend: backend, ledger: ledger)

        #expect(!mover.park(a, display: display, displayID: 1))
        #expect(backend.frames[a] == frameA)
        #expect(ledger.entries().isEmpty)
        #expect(!mover.isParked(a))
    }
}

@Test func parkFailsWhenMoveIsRefused() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA]
        backend.refuseMoves = [a]
        let mover = WindowMover(backend: backend, ledger: ledger)

        #expect(!mover.park(a, display: display, displayID: 1))
        #expect(backend.frames[a] == frameA)
        #expect(ledger.entries().isEmpty)
    }
}

@Test func parkDoesNotMoveWhenLedgerCannotRecord() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }
    let url = dir.appendingPathComponent("parked.json")
    try Data("not a ledger".utf8).write(to: url)
    try makeReadOnly(dir)
    let ledger = ParkingLedger(fileURL: url)
    let backend = FakeBackend()
    backend.frames = [a: frameA]
    let mover = WindowMover(backend: backend, ledger: ledger)

    #expect(!mover.park(a, display: display, displayID: 1))
    #expect(backend.moves.isEmpty)
    #expect(backend.frames[a] == frameA)
}

@Test func parkingAnAlreadyParkedWindowKeepsTrueOriginal() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA]
        let mover = WindowMover(backend: backend, ledger: ledger)

        #expect(mover.park(a, display: display, displayID: 1))
        #expect(mover.park(a, display: display, displayID: 1))
        #expect(ledger.entries().map(\.originalFrame) == [frameA])
        #expect(mover.unpark(a))
        #expect(backend.frames[a] == frameA)
    }
}

@Test func unparkRestoresOriginalFrameAndClearsLedger() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA]
        let mover = WindowMover(backend: backend, ledger: ledger)
        #expect(mover.park(a, display: display, displayID: 1))

        #expect(mover.unpark(a))
        #expect(backend.frames[a] == frameA)
        #expect(ledger.entries().isEmpty)
        #expect(!mover.isParked(a))
    }
}

@Test func unparkKeepsLedgerIfMoveFails() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA]
        let mover = WindowMover(backend: backend, ledger: ledger)
        #expect(mover.park(a, display: display, displayID: 1))
        backend.refuseMoves = [a]

        #expect(!mover.unpark(a))
        #expect(ledger.entries().map(\.window) == [a])
        #expect(mover.isParked(a))
    }
}

@Test func unparkSucceedsWhenAppRoundsWithinOnePoint() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA]
        let mover = WindowMover(backend: backend, ledger: ledger)
        #expect(mover.park(a, display: display, displayID: 1))
        backend.onSetOrigin = { p, w in
            if p == frameA.origin { backend.refuseMoves = [w]; backend.frames[w]?.origin = CGPoint(x: p.x + 0.5, y: p.y - 1) }
        }

        #expect(mover.unpark(a))
        #expect(ledger.entries().isEmpty)
    }
}

@Test func unparkRestoresEvenIfLedgerCannotBeUpdated() throws {
    try withLedger { dir, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA]
        let mover = WindowMover(backend: backend, ledger: ledger)
        #expect(mover.park(a, display: display, displayID: 1))
        try makeReadOnly(dir)

        #expect(mover.unpark(a))
        #expect(backend.frames[a] == frameA)
    }
}

@Test func restoreAllUnparksEverything() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA, b: frameB]
        let first = WindowMover(backend: backend, ledger: ledger)
        #expect(first.park(a, display: display, displayID: 1))
        #expect(first.park(b, display: display, displayID: 1))

        // A different mover instance: restoreAll works from the ledger, not memory.
        WindowMover(backend: backend, ledger: ledger).restoreAll()
        #expect(backend.frames[a] == frameA)
        #expect(backend.frames[b] == frameB)
        #expect(ledger.entries().isEmpty)
    }
}

@Test func restoreAllForgetsWindowsThatNoLongerExist() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA, b: frameB]
        let mover = WindowMover(backend: backend, ledger: ledger)
        #expect(mover.park(a, display: display, displayID: 1))
        #expect(mover.park(b, display: display, displayID: 1))
        backend.frames[b] = nil

        mover.restoreAll()
        #expect(backend.frames[a] == frameA)
        #expect(ledger.entries().isEmpty)
    }
}

@Test func recoverUsesRecoveryActions() throws {
    try withLedger { _, ledger in
        let offScreen = CGRect(x: 3000, y: 100, width: 300, height: 200)
        try ledger.record(ParkedEntry(window: a, bundleID: nil, originalFrame: frameA, displayID: 1))
        try ledger.record(ParkedEntry(window: b, bundleID: nil, originalFrame: offScreen, displayID: 1))
        let dead = WindowRef(pid: 3, windowID: 30)
        try ledger.record(ParkedEntry(window: dead, bundleID: nil, originalFrame: frameA, displayID: 1))
        let backend = FakeBackend()
        backend.frames = [a: CGRect(origin: CGPoint(x: 999, y: 799), size: frameA.size),
                          b: CGRect(origin: CGPoint(x: 999, y: 799), size: offScreen.size)]

        WindowMover(backend: backend, ledger: ledger).recover(visibleScreens: [display])
        #expect(backend.frames[a] == frameA)
        #expect(backend.frames[b] == CGRect(x: 350, y: 300, width: 300, height: 200))
        #expect(ledger.entries().isEmpty)
        #expect(!backend.moves.contains { $0.0 == dead })
    }
}

@Test func recoverKeepsEntryWhenRestoreFails() throws {
    try withLedger { _, ledger in
        try ledger.record(ParkedEntry(window: a, bundleID: nil, originalFrame: frameA, displayID: 1))
        let backend = FakeBackend()
        backend.frames = [a: CGRect(origin: CGPoint(x: 999, y: 799), size: frameA.size)]
        backend.refuseMoves = [a]

        WindowMover(backend: backend, ledger: ledger).recover(visibleScreens: [display])
        #expect(ledger.entries().map(\.window) == [a])
    }
}

@Test func reparkFollowsNewDisplayBounds() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA, b: frameB]
        let mover = WindowMover(backend: backend, ledger: ledger)
        #expect(mover.park(a, display: display, displayID: 1))
        #expect(mover.park(b, display: display, displayID: 1))

        let bigger = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        mover.repark(display: bigger)
        #expect(backend.frames[a]?.origin == CGPoint(x: 1599, y: 999))
        #expect(backend.frames[b]?.origin == CGPoint(x: 1599, y: 999))
        #expect(ledger.entries().map(\.originalFrame) == [frameA, frameB])
    }
}

@Test func restoreAllAndRecoverKeepEntryForLiveWindowThatCannotBeReached() throws {
    try withLedger { _, ledger in
        try ledger.record(ParkedEntry(window: a, bundleID: nil, originalFrame: frameA, displayID: 1))
        let backend = FakeBackend()
        backend.unreachableButLive = [a]
        let mover = WindowMover(backend: backend, ledger: ledger)

        mover.restoreAll()
        #expect(ledger.entries().map(\.window) == [a])
        mover.recover(visibleScreens: [display])
        #expect(ledger.entries().map(\.window) == [a])
    }
}

@Test func unparkFitsFrameFromMissingDisplayOntoRemainingScreen() throws {
    try withLedger { _, ledger in
        let onGoneDisplay = CGRect(x: 1200, y: 100, width: 300, height: 200)
        try ledger.record(ParkedEntry(window: a, bundleID: nil, originalFrame: onGoneDisplay, displayID: 2))
        let backend = FakeBackend()
        backend.frames = [a: CGRect(origin: CGPoint(x: 1999, y: 799), size: onGoneDisplay.size)]
        let mover = WindowMover(backend: backend, ledger: ledger)

        #expect(mover.unpark(a))
        let landed = try #require(backend.frames[a])
        #expect(display.contains(landed))
        #expect(landed == CGRect(x: 350, y: 300, width: 300, height: 200))
        #expect(ledger.entries().isEmpty)
    }
}

@Test func unparkCapsOversizedFrameOnMissingDisplay() throws {
    try withLedger { _, ledger in
        let oversized = CGRect(x: 1200, y: 100, width: 1500, height: 900)
        try ledger.record(ParkedEntry(window: a, bundleID: nil, originalFrame: oversized, displayID: 1))
        let backend = FakeBackend()
        backend.frames = [a: CGRect(origin: CGPoint(x: 999, y: 799), size: oversized.size)]
        let mover = WindowMover(backend: backend, ledger: ledger)

        #expect(mover.unpark(a))
        #expect(backend.frames[a] == display)
        #expect(ledger.entries().isEmpty)
    }
}

@Test func recoverCapsOversizedFrameToScreen() throws {
    try withLedger { _, ledger in
        let oversized = CGRect(x: 100, y: 100, width: 1500, height: 900)
        try ledger.record(ParkedEntry(window: a, bundleID: nil, originalFrame: oversized, displayID: 1))
        let backend = FakeBackend()
        backend.frames = [a: CGRect(origin: CGPoint(x: 999, y: 799), size: oversized.size)]

        WindowMover(backend: backend, ledger: ledger).recover(visibleScreens: [display])
        #expect(backend.frames[a] == display)
        #expect(ledger.entries().isEmpty)
    }
}

private let rightScreen = CGRect(x: 1000, y: 0, width: 1000, height: 800)

@Test func parkFailsWhenCornerShowsOnNeighbouringScreen() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA]
        backend.screens = [display, rightScreen]
        let mover = WindowMover(backend: backend, ledger: ledger)

        #expect(!mover.park(a, display: display, displayID: 1))
        #expect(backend.frames[a] == frameA)
        #expect(ledger.entries().isEmpty)
    }
}

@Test func parkOnRightmostOfTwoScreensSucceeds() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        let onRight = CGRect(x: 1200, y: 100, width: 300, height: 200)
        backend.frames = [a: onRight]
        backend.screens = [display, rightScreen]
        let mover = WindowMover(backend: backend, ledger: ledger)

        #expect(mover.park(a, display: rightScreen, displayID: 2))
        #expect(backend.frames[a]?.origin == CGPoint(x: 1999, y: 799))
    }
}

@Test func reparkThatWouldShowOnNeighbourPutsWindowBackOnStage() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA]
        let mover = WindowMover(backend: backend, ledger: ledger)
        #expect(mover.park(a, display: display, displayID: 1))

        backend.screens = [display, rightScreen]
        mover.repark(display: display)
        #expect(backend.frames[a] == frameA)
        #expect(ledger.entries().isEmpty)
    }
}

@Test func emptyLivenessAnswerForgetsNothing() throws {
    try withLedger { _, ledger in
        try ledger.record(ParkedEntry(window: a, bundleID: nil, originalFrame: frameA, displayID: 1))
        let backend = FakeBackend()  // reports no live windows at all, as when the query fails
        let mover = WindowMover(backend: backend, ledger: ledger)

        mover.restoreAll()
        #expect(ledger.entries().map(\.window) == [a])
        mover.recover(visibleScreens: [display])
        #expect(ledger.entries().map(\.window) == [a])
    }
}

/// Display with a 40-pt Dock strip at the bottom: visible frame is shorter than the full frame.
private let visibleAboveDock = CGRect(x: 0, y: 0, width: 1000, height: 760)

@Test func unparkRestoresExactFrameOverlappingDockOrPastEdge() throws {
    let underDock = CGRect(x: 100, y: 500, width: 300, height: 290)    // bottom under the Dock
    let pastRight = CGRect(x: 800, y: 100, width: 400, height: 300)    // 200 pt past the right edge
    for original in [underDock, pastRight] {
        try withLedger { _, ledger in
            let backend = FakeBackend()
            backend.frames = [a: original]
            backend.screens = [visibleAboveDock]
            backend.fullFrames = [display]
            let mover = WindowMover(backend: backend, ledger: ledger)
            #expect(mover.park(a, display: display, displayID: 1))

            #expect(mover.unpark(a))
            #expect(backend.frames[a] == original)
            #expect(backend.sizeChanges == 0)
            #expect(ledger.entries().isEmpty)
        }
    }
}

@Test func restoreAllRestoresExactReachableFrame() throws {
    try withLedger { _, ledger in
        let pastRight = CGRect(x: 800, y: 100, width: 400, height: 300)
        let backend = FakeBackend()
        backend.frames = [a: pastRight]
        backend.screens = [visibleAboveDock]
        backend.fullFrames = [display]
        let mover = WindowMover(backend: backend, ledger: ledger)
        #expect(mover.park(a, display: display, displayID: 1))

        mover.restoreAll()
        #expect(backend.frames[a] == pastRight)
        #expect(backend.sizeChanges == 0)
    }
}

@Test func unparkFitsFrameWhoseTitleStripIsBarelyOnScreen() throws {
    try withLedger { _, ledger in
        // Only 50 pt of the title strip is on the display: below the 60-pt reach rule.
        let mostlyOff = CGRect(x: 950, y: 100, width: 400, height: 300)
        try ledger.record(ParkedEntry(window: a, bundleID: nil, originalFrame: mostlyOff, displayID: 1))
        let backend = FakeBackend()
        backend.frames = [a: CGRect(origin: CGPoint(x: 999, y: 799), size: mostlyOff.size)]
        let mover = WindowMover(backend: backend, ledger: ledger)

        #expect(mover.unpark(a))
        #expect(backend.frames[a] == CGRect(x: 600, y: 100, width: 400, height: 300))
    }
}

@Test func forgetDropsLedgerEntryWithoutMovingTheWindow() throws {
    try withLedger { _, ledger in
        let backend = FakeBackend()
        backend.frames = [a: frameA, b: frameB]
        let mover = WindowMover(backend: backend, ledger: ledger)
        #expect(mover.park(a, display: display, displayID: 1))
        #expect(mover.park(b, display: display, displayID: 1))
        backend.frames[a] = nil   // the window closed
        let movesBefore = backend.moves.count

        mover.forget(a)
        #expect(ledger.entries().map(\.window) == [b])
        #expect(!mover.isParked(a))
        #expect(backend.moves.count == movesBefore)
        mover.forget(a)           // forgetting an unknown window is a no-op
        #expect(ledger.entries().map(\.window) == [b])
    }
}
