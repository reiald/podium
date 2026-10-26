import Foundation

/// Stage Manager's "Show windows from an application" setting.
///
/// - `allAtOnce`: an app's windows go on stage together.
/// - `oneAtATime`: one window of the app goes on stage; its other windows wait in the
///   app's strip item.
public enum WindowGrouping: String, Codable, Sendable {
    case allAtOnce, oneAtATime
}

/// Windows shown together: the stage, or one strip item. `windows` are front first.
public struct Stage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public internal(set) var windows: [WindowRef]
}

/// Which windows are on stage and which strip items there are, on one display.
///
/// The board stores only the inputs of Apple's Stage Manager assignment (window z-order,
/// user sets, minimized windows, hidden apps, grouping, the proposed front window, the
/// empty-stage flag and the strip's previous order) and recomputes everything else with
/// `assign` (StageAssignment.swift) after each change. Events change inputs as Apple does
/// (docs/specs/2026-10-23-assignment-model-design.md):
///
/// - Focus (`windowFocused`, `show`, `deminimize`, `appActivated`, `select`) proposes a
///   window: it goes to the front and its group comes on stage (R7).
/// - `addToActiveStage`, `combineIntoActive` add windows to the stage's user set, creating
///   one from the stage's windows if needed (R14).
/// - `windowClosed`, `minimize`, `minimizeToStrip`, `appTerminated` and `appHidden` take
///   windows away; if the front window goes, another window of the stage comes to the
///   front, the same app's first, else the stage is left empty (R15, R18).
/// - `showDesktop` empties the stage until the next proposal (R8).
///
/// Stage ids are derived from the group (`stageID(of:)`), so they stay the same across
/// changes. A group on stage that also has windows in the strip (R10) shows them as a
/// strip item with an id of its own.
///
/// Calls naming a window or stage that is not on the board are no-ops.
public struct StageBoard: Equatable, Sendable {
    public let displayID: UInt32
    public let replacementOrder: StripReplacementOrder
    public let maximumRowCount: Int

    private struct Inputs: Equatable, Sendable {
        /// Every board window, most recently focused first.
        var zOrder: [WindowRef] = []
        var userSets: [UserSetID: [WindowRef]] = [:]
        var nextUserSet: UInt32 = 1
        /// In the Dock.
        var docked: Set<WindowRef> = []
        /// Minimized to the strip (parked, with a strip card).
        var minimizedToStrip: Set<WindowRef> = []
        var hidden: Set<Int32> = []
        var grouping: WindowGrouping = .allAtOnce
        var proposal: WindowRef?
        var emptyStage = false
        /// The empty stage came from a wallpaper click; another one brings `proposal`'s
        /// stage back.
        var desktopFromWallpaper = false

        mutating func toFront(_ w: WindowRef) {
            zOrder.removeAll { $0 == w }
            zOrder.insert(w, at: 0)
        }

        /// Takes the windows out of their user sets; a set left with one window is no set.
        mutating func removeFromUserSets(_ windows: Set<WindowRef>) {
            for id in Array(userSets.keys) {
                userSets[id]!.removeAll { windows.contains($0) }
                if userSets[id]!.count < 2 { userSets[id] = nil }
            }
        }
    }

    private var inputs = Inputs()
    private var assignment = Assignment()

    public init(displayID: UInt32, replacementOrder: StripReplacementOrder = .stableLeastRecentlyUsed,
                maximumRowCount: Int = Tuning.initial.maxRowCount) {
        self.displayID = displayID
        self.replacementOrder = replacementOrder
        self.maximumRowCount = maximumRowCount
    }

    public var grouping: WindowGrouping { inputs.grouping }

    /// Whether `w` was sent to the Dock and not yet brought back.
    public func isMinimized(_ w: WindowRef) -> Bool {
        inputs.docked.contains(w)
    }

    /// Whether `w` was minimized to the strip (`minimizeToStrip`) and not yet brought back.
    public func isMinimizedToStrip(_ w: WindowRef) -> Bool {
        inputs.minimizedToStrip.contains(w)
    }

    /// Whether the app is hidden (`appHidden`) and not yet shown again.
    public func isHidden(pid: Int32) -> Bool {
        inputs.hidden.contains(pid)
    }

    public var activeStage: Stage? {
        guard let group = assignment.stageGroup else { return nil }
        let windows = assignment.stageWindows
        return windows.isEmpty ? nil : Stage(id: stageID(of: group), windows: windows)
    }

    public var activeStageID: UUID? { activeStage?.id }

    /// Every stage: the active one first, then the strip's.
    public var stages: [Stage] {
        (activeStage.map { [$0] } ?? []) + stripStages
    }

    /// Strip items in strip order, then hidden apps' windows (which get no slot).
    public var stripStages: [Stage] {
        stripItems.map(\.stage) + hiddenStages
    }

    /// The strip items that get a slot: `stripStages` without windows in the Dock or of
    /// hidden apps, and without items left empty. Those windows have no card (macOS took
    /// them off screen), so a slot for them would be an invisible click target pushing real
    /// items past the last row.
    public var visibleStripStages: [Stage] {
        stripStages.compactMap { s in
            let windows = s.windows.filter { !inputs.docked.contains($0) && !inputs.hidden.contains($0.pid) }
            return windows.isEmpty ? nil : Stage(id: s.id, windows: windows)
        }
    }

    // MARK: Events

    /// A new window comes to the front and is proposed. No-op if already on the board.
    public mutating func windowOpened(_ w: WindowRef) {
        guard !inputs.zOrder.contains(w) else { return }
        update { i in
            i.zOrder.insert(w, at: 0)
            guard !i.hidden.contains(w.pid) else { return }
            i.proposal = w
            i.emptyStage = false
        }
    }

    public mutating func windowClosed(_ w: WindowRef) {
        guard inputs.zOrder.contains(w) else { return }
        leave([w], leavesUserSets: true, fallsBackToPrevious: true) { i in
            i.zOrder.removeAll { $0 == w }
            i.docked.remove(w)
            i.minimizedToStrip.remove(w)
            if i.proposal == w { i.proposal = nil }
        }
    }

    /// `w` comes to the front, back from the Dock or the strip, and its group on stage.
    /// No-op while its app is hidden.
    public mutating func windowFocused(_ w: WindowRef) {
        guard inputs.zOrder.contains(w), !inputs.hidden.contains(w.pid) else { return }
        update { i in
            i.toFront(w)
            i.docked.remove(w)
            i.minimizedToStrip.remove(w)
            i.proposal = w
            i.emptyStage = false
        }
    }

    /// The window came back from the Dock.
    public mutating func deminimize(_ w: WindowRef) {
        windowFocused(w)
    }

    /// The app's most recent window that is not minimized is focused; no-op if it has none.
    public mutating func appActivated(pid: Int32) {
        guard !inputs.hidden.contains(pid),
              let w = inputs.zOrder.first(where: { $0.pid == pid && !isMinimizedAnywhere($0) }) else { return }
        windowFocused(w)
    }

    public mutating func appTerminated(pid: Int32) {
        let windows = Set(inputs.zOrder.filter { $0.pid == pid })
        guard !windows.isEmpty || inputs.hidden.contains(pid) else { return }
        leave(windows, leavesUserSets: true) { i in
            i.hidden.remove(pid)
            i.zOrder.removeAll { windows.contains($0) }
            i.docked.subtract(windows)
            i.minimizedToStrip.subtract(windows)
            if let p = i.proposal, windows.contains(p) { i.proposal = nil }
        }
    }

    /// The app was hidden: its windows leave the stage and the strip (they keep their user
    /// sets). If its window was in front, another window of the stage comes to the front,
    /// else the stage is left empty.
    public mutating func appHidden(pid: Int32) {
        guard !inputs.hidden.contains(pid) else { return }
        leave(Set(inputs.zOrder.filter { $0.pid == pid }), leavesUserSets: false) { $0.hidden.insert(pid) }
    }

    /// The app was shown again: its windows are back in their groups. Bringing them on
    /// stage is the activation's job (`appActivated`).
    public mutating func appUnhidden(pid: Int32) {
        update { $0.hidden.remove(pid) }
    }

    /// Strip click: the item's front window that is not minimized is focused. An item of
    /// minimized windows only first brings its front one back from the strip.
    public mutating func select(stageID: UUID) {
        guard let (_, item) = stripItems.first(where: { $0.stage.id == stageID }) else {
            if stageID == activeStageID, let front = activeStage?.windows.first { windowFocused(front) }
            return
        }
        let target = item.windows.first { !isMinimizedAnywhere($0) }
            ?? item.windows.first { inputs.minimizedToStrip.contains($0) }
        if let target { windowFocused(target) }
    }

    /// App view click: brings exactly `w` to the front. No-op for a window in the Dock.
    public mutating func show(_ w: WindowRef) {
        guard !inputs.docked.contains(w) else { return }
        windowFocused(w)
    }

    /// Switches the grouping; the board follows.
    public mutating func setGrouping(_ g: WindowGrouping) {
        update { $0.grouping = g }
    }

    /// Shift-click / drag-in of one window: it joins the stage's user set (R14). On the
    /// desktop it is just focused.
    public mutating func addToActiveStage(_ w: WindowRef) {
        guard inputs.zOrder.contains(w), !inputs.hidden.contains(w.pid), !inputs.docked.contains(w),
              !assignment.stageWindows.contains(w) else { return }
        guard activeStage != nil else { return windowFocused(w) }
        addToStage([w])
    }

    /// A strip item dropped on the stage (or shift-clicked); `dragged` is the window whose
    /// card was dragged. One at a Time, an app's item gives exactly `dragged` (its front
    /// window if `dragged` is not in it); otherwise all the item's windows join the stage's
    /// user set (R14). On the desktop the window comes on stage as with a click.
    public mutating func combineIntoActive(stageID: UUID, dragged: WindowRef?) {
        guard let (group, item) = stripItems.first(where: { $0.stage.id == stageID }) else { return }
        let windows = item.windows.filter { !inputs.docked.contains($0) }
        let front = dragged.flatMap { windows.contains($0) ? $0 : nil }
            ?? windows.first { !inputs.minimizedToStrip.contains($0) } ?? windows.first
        guard let front else { return }
        guard activeStage != nil else { return windowFocused(front) }
        if case .process = group, grouping == .oneAtATime {
            addToStage([front])
        } else {
            addToStage([front] + windows.filter { $0 != front })
        }
    }

    /// Minimize to strip, and a drag out of the stage: `w` stays in its group, minimized,
    /// and shows in the strip under its app (R5, R10). It leaves its user set (R15).
    public mutating func minimizeToStrip(_ w: WindowRef) {
        guard inputs.zOrder.contains(w), !isMinimizedAnywhere(w) else { return }
        leave([w], leavesUserSets: true) { $0.minimizedToStrip.insert(w) }
    }

    /// Wallpaper click: the stage is left empty (desktop) until a window is proposed. No-op
    /// on the desktop.
    public mutating func showDesktop() {
        guard activeStage != nil else { return }
        update { i in
            i.emptyStage = true
            i.desktopFromWallpaper = true
        }
    }

    /// The desktop shows because of a wallpaper click, and the stage it cleared is still
    /// there to bring back.
    public var canReturnFromDesktop: Bool {
        guard inputs.desktopFromWallpaper, let p = inputs.proposal else { return false }
        return !isMinimizedAnywhere(p) && !inputs.hidden.contains(p.pid)
    }

    /// A second wallpaper click: the stage the first one cleared comes back.
    public mutating func returnFromDesktop() {
        guard canReturnFromDesktop else { return }
        update { $0.emptyStage = false }
    }

    /// `w` went to the Dock. It leaves its user set.
    public mutating func minimize(_ w: WindowRef) {
        guard inputs.zOrder.contains(w), !inputs.docked.contains(w) else { return }
        leave([w], leavesUserSets: true) { i in
            i.minimizedToStrip.remove(w)
            i.docked.insert(w)
        }
    }

    /// `new` replaces `old` (same document, new window): it takes `old`'s place in the
    /// z-order and in its user set (R16).
    public mutating func windowReplaced(old: WindowRef, new: WindowRef) {
        guard old != new, inputs.zOrder.contains(old) else { return }
        update { i in
            i.zOrder.removeAll { $0 == new }
            i.zOrder = i.zOrder.map { $0 == old ? new : $0 }
            for id in Array(i.userSets.keys) {
                i.userSets[id]!.removeAll { $0 == new }
                i.userSets[id] = i.userSets[id]!.map { $0 == old ? new : $0 }
            }
            i.docked.remove(old)
            i.minimizedToStrip.remove(old)
            if i.proposal == old { i.proposal = new }
        }
    }

    /// Recency of `w`: higher was focused more recently, 0 not on the board.
    func lastFocus(of w: WindowRef) -> Int {
        inputs.zOrder.firstIndex(of: w).map { inputs.zOrder.count - $0 } ?? 0
    }

    // MARK: Helpers

    private func isMinimizedAnywhere(_ w: WindowRef) -> Bool {
        inputs.docked.contains(w) || inputs.minimizedToStrip.contains(w)
    }

    /// The assigned strip items with their groups. A stage group's own item (R10) holds
    /// its windows off stage and has an id of its own.
    private var stripItems: [(group: GroupID, stage: Stage)] {
        let onStage = Set(assignment.stageWindows)
        return assignment.strip.compactMap { id in
            guard let group = assignment.group(id) else { return nil }
            let windows = group.windows.filter { !onStage.contains($0) }
            guard !windows.isEmpty else { return nil }
            let role: StageIDRole = id == assignment.stageGroup && !onStage.isEmpty ? .rest : .group
            return (id, Stage(id: stageID(of: id, role: role), windows: windows))
        }
    }

    /// Hidden apps' windows, grouped as they would be: still on the board, never on stage
    /// or in a slot.
    private var hiddenStages: [Stage] {
        guard !inputs.hidden.isEmpty else { return [] }
        let windows = inputs.zOrder.filter { inputs.hidden.contains($0.pid) }
        return containerGroups(zOrder: windows, userSets: inputs.userSets,
                               minimized: inputs.docked.union(inputs.minimizedToStrip), hidden: [],
                               grouping: inputs.grouping)
            .map { Stage(id: stageID(of: $0.id, role: .hidden), windows: $0.windows) }
    }

    /// Adds `windows` (front first) to the stage's user set, creating it from the stage's
    /// windows if the stage is not one yet, and brings them to the front (R14).
    private mutating func addToStage(_ windows: [WindowRef]) {
        let stageWindows = assignment.stageWindows
        let stageSet = assignment.stageWindowSet
        let adding = windows.filter { !stageWindows.contains($0) }
        guard let front = adding.first else { return }
        update { i in
            i.minimizedToStrip.subtract(adding)
            i.removeFromUserSets(Set(adding))
            if case let .userSet(id) = stageSet, i.userSets[id] != nil {
                i.userSets[id]! += adding
            } else {
                let id = UserSetID(i.nextUserSet)
                i.nextUserSet += 1
                i.userSets[id] = stageWindows + adding
            }
            for w in adding.reversed() { i.toFront(w) }
            i.proposal = front
            i.emptyStage = false
        }
    }

    /// Applies `change`, which takes `leaving` off the stage. If the stage's front window
    /// leaves, another window of the stage comes to the front, the same app's first; with
    /// none left the stage is empty (R15, R18).
    /// `fallsBackToPrevious` (a close): a stage left with nothing brings back the most
    /// recently used window's stage instead of the desktop.
    private mutating func leave(_ leaving: Set<WindowRef>, leavesUserSets: Bool, fallsBackToPrevious: Bool = false,
                                _ change: (inout Inputs) -> Void) {
        let stageWindows = assignment.stageWindows
        let front = inputs.proposal.flatMap { stageWindows.contains($0) ? $0 : nil } ?? stageWindows.first
        update { i in
            change(&i)
            if leavesUserSets { i.removeFromUserSets(leaving) }
            guard let front, leaving.contains(front) else { return }
            let next = stageWindows.filter { w in
                !leaving.contains(w) && i.zOrder.contains(w) && !i.docked.contains(w)
                    && !i.minimizedToStrip.contains(w) && !i.hidden.contains(w.pid)
            }
            if let n = next.first(where: { $0.pid == front.pid }) ?? next.first {
                i.toFront(n)
                i.proposal = n
            } else if fallsBackToPrevious, let previous = i.zOrder.first(where: { w in
                !leaving.contains(w) && !i.docked.contains(w) && !i.minimizedToStrip.contains(w) && !i.hidden.contains(w.pid)
            }) {
                i.proposal = previous
            } else {
                i.proposal = nil
                i.emptyStage = true
            }
        }
    }

    /// Applies `change` to the inputs and, if they changed, recomputes the assignment.
    private mutating func update(_ change: (inout Inputs) -> Void) {
        var next = inputs
        change(&next)
        if !next.emptyStage || next.proposal == nil { next.desktopFromWallpaper = false }
        guard next != inputs else { return }
        inputs = next
        assignment = assign(AssignmentInput(
            zOrder: inputs.zOrder, userSets: inputs.userSets,
            minimized: inputs.docked.union(inputs.minimizedToStrip), hidden: inputs.hidden,
            grouping: inputs.grouping, proposal: inputs.proposal, emptyStage: inputs.emptyStage,
            replacementOrder: replacementOrder, maximumRowCount: maximumRowCount, previous: assignment.state))
    }
}

/// Which stage of a group an id names.
enum StageIDRole: UInt8 {
    /// The group: on stage, or its strip item when it is not on stage.
    case group = 0
    /// The strip item of a group on stage: its windows off stage (R10).
    case rest = 1
    /// A hidden app's windows.
    case hidden = 2
}

/// A UUID made of the group and the role, with version nibble 5. App window items use
/// nibble 8 (`appWindowItemID`), so the two never collide.
func stageID(of group: GroupID, role: StageIDRole = .group) -> UUID {
    let (kind, value): (UInt8, UInt32)
    switch group {
    case let .process(pid): (kind, value) = (1, UInt32(bitPattern: pid))
    case let .crossAppSet(id): (kind, value) = (2, id.value)
    }
    func byte(_ shift: UInt32) -> UInt8 { UInt8(truncatingIfNeeded: value >> shift) }
    return UUID(uuid: (kind, role.rawValue, 0, 0, 0, 0, 0x50, 0, 0x80, 0, 0, 0,
                       byte(24), byte(16), byte(8), byte(0)))
}
