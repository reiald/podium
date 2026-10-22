import Foundation

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
/// Calls naming a window or stage that is not on the board are no-ops.
public struct StageBoard: Equatable, Sendable {
    public let displayID: UInt32
    public private(set) var stages: [Stage] = []
    public private(set) var activeStageID: UUID?

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
        if let active = activeStageID, let i = index(of: active),
           stages[i].windows.contains(where: { $0.pid == w.pid }) {
            insert(w, intoStageAt: i)
        } else if let i = stageOfMostRecentWindow(pid: w.pid) {
            insert(w, intoStageAt: i)
            activate(stageID: stages[i].id)
        } else {
            activate(newStageWith: w)
        }
    }

    public mutating func windowClosed(_ w: WindowRef) {
        remove { $0 == w }
    }

    /// Records `w` as most recently focused and activates its stage.
    public mutating func windowFocused(_ w: WindowRef) {
        guard let i = stageIndex(of: w) else { return }
        minimized.remove(w)
        touch(w)
        sortWindows(inStageAt: i)
        activate(stageID: stages[i].id)
    }

    /// The window came back from the Dock: unmarks it and treats it as focused.
    public mutating func deminimize(_ w: WindowRef) {
        windowFocused(w)
    }

    /// Activates the stage holding the app's most recently focused non-minimized window;
    /// no-op if the app has none.
    public mutating func appActivated(pid: Int32) {
        guard let i = stageOfMostRecentWindow(pid: pid) else { return }
        activate(stageID: stages[i].id)
    }

    public mutating func appTerminated(pid: Int32) {
        remove { $0.pid == pid }
    }

    /// Makes the stage active and most recently used. `nil` shows the desktop.
    public mutating func activate(stageID: UUID?) {
        guard let stageID else {
            activeStageID = nil
            return
        }
        guard index(of: stageID) != nil else { return }
        activeStageID = stageID
        mru.removeAll { $0 == stageID }
        mru.insert(stageID, at: 0)
    }

    /// Shift-click / drag-in: moves `w` into the active stage, creating one if there is none.
    public mutating func addToActiveStage(_ w: WindowRef) {
        guard let from = stageIndex(of: w), stages[from].id != activeStageID else { return }
        let fromID = stages[from].id
        touch(w)
        if let active = activeStageID, index(of: active) != nil {
            detach(w, fromStageAt: from)
            insert(w, intoStageAt: index(of: active)!)
            activate(stageID: active)
        } else {
            // Desktop: the window's stage simply becomes the active one if it is alone.
            if stages[from].windows.count == 1 {
                activate(stageID: fromID)
            } else {
                detach(w, fromStageAt: from)
                activate(newStageWith: w)
            }
        }
    }

    /// Merges the stage into the active one. No-op if it is the active stage or none is active.
    public mutating func combineIntoActive(stageID: UUID) {
        guard let active = activeStageID, active != stageID,
              let from = index(of: stageID), let to = index(of: active) else { return }
        stages[to].windows += stages[from].windows
        sortWindows(inStageAt: to)
        stages.remove(at: from)
        mru.removeAll { $0 == stageID }
        activate(stageID: active)
    }

    /// Drag-out: moves `w` into its own new stage and activates it.
    public mutating func moveToOwnStage(_ w: WindowRef) {
        guard let from = stageIndex(of: w), stages[from].windows.count > 1 else { return }
        touch(w)
        detach(w, fromStageAt: from)
        activate(newStageWith: w)
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
            return
        }
        detach(w, fromStageAt: from)
        let stage = Stage(id: UUID(), windows: [w])
        stages.append(stage)
        mru.insert(stage.id, at: 0)
    }

    // MARK: Helpers

    private func index(of id: UUID) -> Int? { stages.firstIndex { $0.id == id } }
    private func stage(_ id: UUID) -> Stage? { stages.first { $0.id == id } }
    private func stageIndex(of w: WindowRef) -> Int? { stages.firstIndex { $0.windows.contains(w) } }

    /// Index of the stage holding the app's most recently focused non-minimized window.
    private func stageOfMostRecentWindow(pid: Int32) -> Int? {
        let best = stages.flatMap { $0.windows }
            .filter { $0.pid == pid && !minimized.contains($0) }
            .max { (focusTick[$0] ?? 0) < (focusTick[$1] ?? 0) }
        return best.flatMap(stageIndex(of:))
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
        activate(stageID: stage.id)
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
