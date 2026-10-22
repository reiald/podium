import Foundation

/// Stage Manager's "Show windows from an application" setting.
///
/// - `allAtOnce`: an app's windows go on stage together.
/// - `oneAtATime`: switching to an app puts only its most recently used window on stage; the
///   app's other windows wait in one pile (one strip stage of that app's windows only).
public enum WindowGrouping: String, Codable, Sendable {
    case allAtOnce, oneAtATime
}

/// A group of windows shown together. `windows` are in most-recently-focused order.
public struct Stage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public internal(set) var windows: [WindowRef]
}

/// Single source of truth for which windows form which stage on one display,
/// and which stage is on screen. Follows Apple's Stage Manager grouping rules:
///
/// - `windowOpened`: if the app has windows in the active stage, add to it; else if the app
///   has windows in another stage, add there and activate that stage; else create a new stage
///   and activate it.
/// - `appActivated(pid)`: activate the stage holding that app's most recently focused window;
///   no-op if the app has none.
/// - `windowClosed` / `appTerminated`: remove the windows; delete stages that become empty;
///   if the active stage was deleted, `activeStageID = nil` (empty stage = desktop).
/// - `minimize(w)`: move `w` to a new non-active stage at the front of the strip; if the
///   active stage becomes empty, `activeStageID = nil`. `w` stays marked minimized until it
///   is focused or `deminimize(w)` is called; `appActivated` and `windowOpened` never pick a
///   minimized window as the app's most recent one.
/// - Activating a stage makes it the most recently used.
///
/// With `grouping == .oneAtATime` (`allAtOnce` is the default and follows only the rules above):
///
/// - A *pile* is a strip stage of two or more windows of one app. After every mutation each
///   app has at most one pile-or-single-app strip stage: they merge into the one nearest the
///   front of the strip, keeping its window order. Stages holding a minimized window and
///   stages mixing apps (manual combines) never merge.
/// - Bringing a window of a pile on stage (`windowFocused`, `appActivated`, `activate`,
///   `select`) gives it a new stage of its own; the app's windows that were on stage join its
///   pile at the front (at the back for `select`, so repeated clicks cycle through the pile);
///   other apps' windows stay together and go to the strip.
/// - `windowOpened`: the app's windows on stage join its pile and the new window takes their
///   place in the active stage; if the app had none there, it gets a new active stage.
/// - `combineIntoActive` of a pile adds only its front window to the active stage.
///
/// Calls naming a window or stage that is not on the board are no-ops.
public struct StageBoard: Equatable, Sendable {
    public let displayID: UInt32
    public private(set) var stages: [Stage] = []
    public private(set) var activeStageID: UUID?
    public private(set) var grouping: WindowGrouping = .allAtOnce

    /// Stage IDs, most recently used first.
    private var mru: [UUID] = []
    /// Monotonic focus counter value per window (higher = more recently focused).
    private var focusTick: [WindowRef: Int] = [:]
    private var clock = 0
    /// Windows sent to the Dock and not yet brought back.
    private var minimized: Set<WindowRef> = []

    public init(displayID: UInt32) {
        self.displayID = displayID
    }

    /// Whether `w` was sent to the Dock and not yet brought back.
    public func isMinimized(_ w: WindowRef) -> Bool {
        minimized.contains(w)
    }

    public var activeStage: Stage? {
        activeStageID.flatMap(stage(_:))
    }

    /// Non-active stages, most recently used first.
    public var stripStages: [Stage] {
        mru.filter { $0 != activeStageID }.compactMap(stage(_:))
    }

    /// The strip stages that get a slot: `stripStages` minus stages whose windows are all
    /// in the Dock. Those have no card (the Dock took them off screen), so a slot for them
    /// would be an invisible click target pushing real stages past the last row.
    public var visibleStripStages: [Stage] {
        stripStages.filter { !$0.windows.allSatisfy(minimized.contains) }
    }

    // MARK: Events

    /// Adds a new window per the grouping rules above. No-op if already on the board.
    public mutating func windowOpened(_ w: WindowRef) {
        guard stageIndex(of: w) == nil else { return }
        touch(w)
        if grouping == .oneAtATime {
            defer { mergePiles() }
            if let a = activeIndex, stages[a].windows.contains(where: { $0.pid == w.pid }) {
                let displaced = stages[a].windows.filter { $0.pid == w.pid }
                stages[a].windows.removeAll { $0.pid == w.pid }
                insert(w, intoStageAt: a)
                pushToPile(displaced, atBack: false)
            } else {
                activate(newStageWith: w)
            }
            return
        }
        if let active = activeStageID, let i = index(of: active),
           stages[i].windows.contains(where: { $0.pid == w.pid }) {
            insert(w, intoStageAt: i)
        } else if let i = stageOfMostRecentWindow(pid: w.pid) {
            insert(w, intoStageAt: i)
            setActive(stages[i].id)
        } else {
            activate(newStageWith: w)
        }
    }

    public mutating func windowClosed(_ w: WindowRef) {
        remove { $0 == w }
        mergePiles()
    }

    /// Records `w` as most recently focused and activates its stage.
    public mutating func windowFocused(_ w: WindowRef) {
        guard let i = stageIndex(of: w) else { return }
        minimized.remove(w)
        touch(w)
        if isPile(at: i) {
            bringOnStageAlone(w, displacedToBack: false)
            return
        }
        sortWindows(inStageAt: i)
        setActive(stages[i].id)
        mergePiles()
    }

    /// The window came back from the Dock: unmarks it and treats it as focused.
    public mutating func deminimize(_ w: WindowRef) {
        windowFocused(w)
    }

    /// Activates the stage holding the app's most recently focused non-minimized window;
    /// no-op if the app has none.
    public mutating func appActivated(pid: Int32) {
        guard let i = stageOfMostRecentWindow(pid: pid) else { return }
        if isPile(at: i), let best = mostRecentWindow(pid: pid) {
            bringOnStageAlone(best, displacedToBack: false)
            return
        }
        setActive(stages[i].id)
        mergePiles()
    }

    public mutating func appTerminated(pid: Int32) {
        remove { $0.pid == pid }
        mergePiles()
    }

    /// Makes the stage active and most recently used. `nil` shows the desktop. One at a Time:
    /// activating a pile brings only its front window on stage.
    public mutating func activate(stageID: UUID?) {
        if let stageID, let i = index(of: stageID), isPile(at: i) {
            bringOnStageAlone(stages[i].windows[0], displacedToBack: false)
            return
        }
        setActive(stageID)
        mergePiles()
    }

    /// Strip click: activates the stage and makes its front window the most recently focused
    /// one. One at a Time, a pile's front window comes on stage alone and the app's window
    /// that was on stage goes to the back of the pile, so repeated clicks cycle through it.
    public mutating func select(stageID: UUID) {
        if let i = index(of: stageID), isPile(at: i) {
            let front = stages[i].windows[0]
            touch(front)
            bringOnStageAlone(front, displacedToBack: true)
            return
        }
        activate(stageID: stageID)
        if let front = activeStage?.windows.first { windowFocused(front) }
    }

    /// Switches the grouping and restructures the board to match. To One at a Time: the
    /// active stage keeps each app's most recent window; the app's other windows join its
    /// pile. To All at Once: the piles of apps on the active stage rejoin it.
    public mutating func setGrouping(_ g: WindowGrouping) {
        guard g != grouping else { return }
        grouping = g
        guard let a = activeIndex else {
            mergePiles()
            return
        }
        switch g {
        case .oneAtATime:
            var seen: Set<Int32> = []
            let displaced = stages[a].windows.filter { !seen.insert($0.pid).inserted }
            stages[a].windows.removeAll { displaced.contains($0) }
            var pids: [Int32] = []
            for w in displaced where !pids.contains(w.pid) { pids.append(w.pid) }
            for pid in pids.reversed() { pushToPile(displaced.filter { $0.pid == pid }, atBack: false) }
            mergePiles()
        case .allAtOnce:
            let activeID = stages[a].id
            let pids = Set(stages[a].windows.map(\.pid))
            for id in mru where id != activeID {
                guard let i = index(of: id), let pid = singleApp(at: i), pids.contains(pid) else { continue }
                let windows = stages[i].windows
                deleteStage(at: i)
                let to = index(of: activeID)!
                stages[to].windows += windows
                sortWindows(inStageAt: to)
            }
        }
    }

    /// Shift-click / drag-in: moves `w` into the active stage, creating one if there is none.
    public mutating func addToActiveStage(_ w: WindowRef) {
        guard let from = stageIndex(of: w), stages[from].id != activeStageID else { return }
        let fromID = stages[from].id
        touch(w)
        if let active = activeStageID, index(of: active) != nil {
            detach(w, fromStageAt: from)
            insert(w, intoStageAt: index(of: active)!)
            setActive(active)
        } else {
            // Desktop: the window's stage simply becomes the active one if it is alone.
            if stages[from].windows.count == 1 {
                setActive(fromID)
            } else {
                detach(w, fromStageAt: from)
                activate(newStageWith: w)
            }
        }
        mergePiles()
    }

    /// Merges the stage into the active one. No-op if it is the active stage or none is active.
    public mutating func combineIntoActive(stageID: UUID) {
        guard let active = activeStageID, active != stageID,
              let from = index(of: stageID), let to = index(of: active) else { return }
        if isPile(at: from) {
            addToActiveStage(stages[from].windows[0])
            return
        }
        stages[to].windows += stages[from].windows
        sortWindows(inStageAt: to)
        stages.remove(at: from)
        mru.removeAll { $0 == stageID }
        setActive(active)
        mergePiles()
    }

    /// Drag-out: moves `w` into its own new stage and activates it.
    public mutating func moveToOwnStage(_ w: WindowRef) {
        guard let from = stageIndex(of: w), stages[from].windows.count > 1 else { return }
        touch(w)
        detach(w, fromStageAt: from)
        activate(newStageWith: w)
        mergePiles()
    }

    /// One at a Time's minimize to strip and drag-out: `w` leaves the active stage for the
    /// front of its app's pile (a new strip stage if the app has none), which moves to the
    /// front of the strip. If the active stage becomes empty, `activeStageID = nil`.
    public mutating func moveToPile(_ w: WindowRef) {
        guard let a = activeIndex, stages[a].windows.contains(w) else { return }
        detach(w, fromStageAt: a)
        pushToPile([w], atBack: false)
        mergePiles()
    }

    public mutating func minimize(_ w: WindowRef) {
        guard let from = stageIndex(of: w) else { return }
        minimized.insert(w)
        if stages[from].windows.count == 1 {
            // Already alone: just push its stage to the front of the strip.
            let id = stages[from].id
            mru.removeAll { $0 == id }
            mru.insert(id, at: 0)
            if activeStageID == id { activeStageID = nil }
            mergePiles()
            return
        }
        detach(w, fromStageAt: from)
        let stage = Stage(id: UUID(), windows: [w])
        stages.append(stage)
        mru.insert(stage.id, at: 0)
        mergePiles()
    }

    // MARK: Helpers

    private func index(of id: UUID) -> Int? { stages.firstIndex { $0.id == id } }
    private func stage(_ id: UUID) -> Stage? { stages.first { $0.id == id } }
    private func stageIndex(of w: WindowRef) -> Int? { stages.firstIndex { $0.windows.contains(w) } }
    private var activeIndex: Int? { activeStageID.flatMap(index(of:)) }

    /// Index of the stage holding the app's most recently focused non-minimized window.
    private func stageOfMostRecentWindow(pid: Int32) -> Int? {
        mostRecentWindow(pid: pid).flatMap(stageIndex(of:))
    }

    private func mostRecentWindow(pid: Int32) -> WindowRef? {
        stages.flatMap { $0.windows }
            .filter { $0.pid == pid && !minimized.contains($0) }
            .max { (focusTick[$0] ?? 0) < (focusTick[$1] ?? 0) }
    }

    /// The app of a strip stage whose windows all belong to one app and none is minimized.
    private func singleApp(at i: Int) -> Int32? {
        let windows = stages[i].windows
        guard stages[i].id != activeStageID, let pid = windows.first?.pid,
              windows.allSatisfy({ $0.pid == pid && !minimized.contains($0) }) else { return nil }
        return pid
    }

    /// One at a Time: a strip stage of several windows of one app.
    private func isPile(at i: Int) -> Bool {
        grouping == .oneAtATime && stages[i].windows.count > 1 && singleApp(at: i) != nil
    }

    private mutating func setActive(_ stageID: UUID?) {
        guard let stageID else {
            activeStageID = nil
            return
        }
        guard index(of: stageID) != nil else { return }
        activeStageID = stageID
        mru.removeAll { $0 == stageID }
        mru.insert(stageID, at: 0)
    }

    /// `w` (in a strip stage) gets a new active stage of its own; the app's windows on the
    /// old active stage join its pile, the rest of that stage goes to the strip.
    private mutating func bringOnStageAlone(_ w: WindowRef, displacedToBack: Bool) {
        guard let from = stageIndex(of: w) else { return }
        detach(w, fromStageAt: from)
        if let a = activeIndex {
            let displaced = stages[a].windows.filter { $0.pid == w.pid }
            for d in displaced { detach(d, fromStageAt: activeIndex!) }
            pushToPile(displaced, atBack: displacedToBack)
        }
        activate(newStageWith: w)
        mergePiles()
    }

    /// Adds `windows` (one app's, off the stage) to that app's pile, at its front or back,
    /// and moves the pile to the front of the strip. Creates the pile if the app has none.
    private mutating func pushToPile(_ windows: [WindowRef], atBack: Bool) {
        guard let pid = windows.first?.pid else { return }
        let id: UUID
        if let id0 = mru.first(where: { id in index(of: id).flatMap(singleApp(at:)) == pid }),
           let i = index(of: id0) {
            id = id0
            stages[i].windows = atBack ? stages[i].windows + windows : windows + stages[i].windows
        } else {
            id = UUID()
            stages.append(Stage(id: id, windows: windows))
        }
        // Front of the strip, but behind the active stage: a stage leaving the stage later
        // still comes before the pile in most-recently-used order.
        mru.removeAll { $0 == id }
        mru.insert(id, at: 0)
        if let active = activeStageID {
            mru.removeAll { $0 == active }
            mru.insert(active, at: 0)
        }
    }

    /// One at a Time: merges each app's single-app strip stages into the one nearest the
    /// front of the strip (its windows first, then the others' in strip order).
    private mutating func mergePiles() {
        guard grouping == .oneAtATime else { return }
        var pileOf: [Int32: UUID] = [:]
        for id in mru {
            guard let i = index(of: id), let pid = singleApp(at: i) else { continue }
            guard let target = pileOf[pid] else {
                pileOf[pid] = id
                continue
            }
            let windows = stages[i].windows
            deleteStage(at: i)
            stages[index(of: target)!].windows += windows
        }
    }

    private mutating func touch(_ w: WindowRef) {
        clock += 1
        focusTick[w] = clock
    }

    private mutating func sortWindows(inStageAt i: Int) {
        stages[i].windows.sort { (focusTick[$0] ?? 0) > (focusTick[$1] ?? 0) }
    }

    private mutating func insert(_ w: WindowRef, intoStageAt i: Int) {
        stages[i].windows.append(w)
        sortWindows(inStageAt: i)
    }

    private mutating func activate(newStageWith w: WindowRef) {
        let stage = Stage(id: UUID(), windows: [w])
        stages.append(stage)
        mru.append(stage.id)
        setActive(stage.id)
    }

    /// Removes `w` from a stage that is known to have other windows.
    private mutating func detach(_ w: WindowRef, fromStageAt i: Int) {
        stages[i].windows.removeAll { $0 == w }
        if stages[i].windows.isEmpty { deleteStage(at: i) }
    }

    private mutating func deleteStage(at i: Int) {
        let id = stages[i].id
        stages.remove(at: i)
        mru.removeAll { $0 == id }
        if activeStageID == id { activeStageID = nil }
    }

    private mutating func remove(where predicate: (WindowRef) -> Bool) {
        for i in stages.indices.reversed() {
            stages[i].windows.removeAll { w in
                let hit = predicate(w)
                if hit {
                    focusTick[w] = nil
                    minimized.remove(w)
                }
                return hit
            }
            if stages[i].windows.isEmpty { deleteStage(at: i) }
        }
    }
}
