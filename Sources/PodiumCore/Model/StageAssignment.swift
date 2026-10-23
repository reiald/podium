import Foundation

// Apple's Stage Manager assignment, as a pure function of a few inputs
// (docs/research/2026-10-23-apple-stage-assignment.md, rules R1–R13).

/// A set of windows the user combined (drag onto the stage, shift-click).
public struct UserSetID: Hashable, Comparable, Sendable {
    public let value: UInt32
    public init(_ value: UInt32) { self.value = value }
    public static func < (a: UserSetID, b: UserSetID) -> Bool { a.value < b.value }
}

/// A container group: one strip item. An app's windows (`process`), or a user set that
/// spans several apps (`crossAppSet`).
public enum GroupID: Hashable, Sendable {
    case process(Int32)
    case crossAppSet(UserSetID)
}

/// A window set inside a group: what comes on stage together.
public enum WindowSetID: Hashable, Sendable {
    /// All at Once: every loose window of the app.
    case process(Int32)
    /// One at a Time: one loose window.
    case window(WindowRef)
    case userSet(UserSetID)
    case minimized(WindowRef)

    public var isMinimized: Bool {
        if case .minimized = self { return true }
        return false
    }
}

public struct WindowSet: Equatable, Sendable {
    public var id: WindowSetID
    /// Front first.
    public var windows: [WindowRef]
    public init(_ id: WindowSetID, _ windows: [WindowRef]) {
        self.id = id
        self.windows = windows
    }
}

public struct ContainerGroup: Equatable, Sendable {
    public var id: GroupID
    /// In z-order.
    public var sets: [WindowSet]
    public init(_ id: GroupID, _ sets: [WindowSet]) {
        self.id = id
        self.sets = sets
    }
    public var windows: [WindowRef] { sets.flatMap(\.windows) }
}

/// Apple's `StageManagerStripReplacementOrder`.
public enum StripReplacementOrder: Sendable {
    /// Strip order is group order: most recent first.
    case recency
    /// The first `maximumRowCount` strip slots keep their groups; a vacated slot goes to the
    /// group that just left the stage.
    case stableLeastRecentlyUsed
}

/// What the strip ordering remembers between updates (Apple's `ComponentState`).
public struct StripState: Equatable, Sendable {
    public var sortedStrip: [GroupID]
    public var stageGroup: GroupID?
    public init(sortedStrip: [GroupID] = [], stageGroup: GroupID? = nil) {
        self.sortedStrip = sortedStrip
        self.stageGroup = stageGroup
    }
}

public struct AssignmentInput: Sendable {
    /// Every window, most recently focused first.
    public var zOrder: [WindowRef]
    public var userSets: [UserSetID: [WindowRef]]
    public var minimized: Set<WindowRef>
    /// Apps whose windows are left out.
    public var hidden: Set<Int32>
    public var grouping: WindowGrouping
    /// The window that should be in front (Apple's `currentWindowProposal`).
    public var proposal: WindowRef?
    /// Show the desktop (Apple's `stageStyle == .empty`).
    public var emptyStage: Bool
    public var replacementOrder: StripReplacementOrder
    public var maximumRowCount: Int
    public var previous: StripState

    public init(zOrder: [WindowRef], userSets: [UserSetID: [WindowRef]] = [:], minimized: Set<WindowRef> = [],
                hidden: Set<Int32> = [], grouping: WindowGrouping = .allAtOnce, proposal: WindowRef? = nil,
                emptyStage: Bool = false, replacementOrder: StripReplacementOrder = .stableLeastRecentlyUsed,
                maximumRowCount: Int = 6, previous: StripState = StripState()) {
        self.zOrder = zOrder
        self.userSets = userSets
        self.minimized = minimized
        self.hidden = hidden
        self.grouping = grouping
        self.proposal = proposal
        self.emptyStage = emptyStage
        self.replacementOrder = replacementOrder
        self.maximumRowCount = maximumRowCount
        self.previous = previous
    }
}

public struct Assignment: Equatable, Sendable {
    /// Every group, in order (front window first).
    public var groups: [ContainerGroup]
    public var stageGroup: GroupID?
    public var stageWindowSet: WindowSetID?
    /// Strip items, in strip order. Can include the stage group (R10).
    public var strip: [GroupID]

    public init(groups: [ContainerGroup] = [], stageGroup: GroupID? = nil, stageWindowSet: WindowSetID? = nil,
                strip: [GroupID] = []) {
        self.groups = groups
        self.stageGroup = stageGroup
        self.stageWindowSet = stageWindowSet
        self.strip = strip
    }

    /// The state the next update's strip ordering starts from.
    public var state: StripState { StripState(sortedStrip: strip, stageGroup: stageGroup) }

    public func group(_ id: GroupID) -> ContainerGroup? { groups.first { $0.id == id } }

    /// The windows on stage, front first.
    public var stageWindows: [WindowRef] {
        guard let stageGroup, let stageWindowSet else { return [] }
        return group(stageGroup)?.sets.first { $0.id == stageWindowSet }?.windows ?? []
    }
}

/// Groups and their window sets (R1–R6): one group per app, a cross-app user set in a
/// group of its own; All at Once merges an app's loose windows; minimized windows split
/// into sets of their own.
public func containerGroups(zOrder: [WindowRef], userSets: [UserSetID: [WindowRef]], minimized: Set<WindowRef>,
                            hidden: Set<Int32>, grouping: WindowGrouping) -> [ContainerGroup] {
    let windows = zOrder.filter { !hidden.contains($0.pid) }
    let rank = Dictionary(windows.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    // Each user set's windows that are present, in z-order.
    var members: [UserSetID: [WindowRef]] = [:]
    var setOf: [WindowRef: UserSetID] = [:]
    for (id, ws) in userSets.sorted(by: { $0.key < $1.key }) {
        let present = ws.filter { rank[$0] != nil && setOf[$0] == nil }.sorted { rank[$0]! < rank[$1]! }
        guard !present.isEmpty else { continue }
        members[id] = present
        for w in present { setOf[w] = id }
    }
    func isCrossApp(_ id: UserSetID) -> Bool { Set(members[id]!.map(\.pid)).count > 1 }

    // R1, R4, R6: groups in the order their first window is visited.
    var result: [ContainerGroup] = []
    var built: Set<GroupID> = []
    for w in windows {
        if let id = setOf[w], isCrossApp(id) {
            guard built.insert(.crossAppSet(id)).inserted else { continue }
            result.append(ContainerGroup(.crossAppSet(id), [WindowSet(.userSet(id), members[id]!)]))
            continue
        }
        guard built.insert(.process(w.pid)).inserted else { continue }
        // The whole app group at once, in z-order, without its cross-app windows.
        var sets: [WindowSet] = []
        var added: Set<UserSetID> = []
        for v in windows where v.pid == w.pid {
            if let id = setOf[v] {
                if isCrossApp(id) || !added.insert(id).inserted { continue }
                sets.append(WindowSet(.userSet(id), members[id]!))
            } else {
                sets.append(WindowSet(.window(v), [v]))
            }
        }
        result.append(ContainerGroup(.process(w.pid), sets))
    }
    return result.map { reshaped($0, minimized: minimized, grouping: grouping) }
}

/// R2: All at Once, an app's loose windows become one set where the first of them was.
/// R5: each minimized window becomes a set of its own, before the rest of its set if it
/// was that set's front window, else after it.
private func reshaped(_ group: ContainerGroup, minimized: Set<WindowRef>, grouping: WindowGrouping) -> ContainerGroup {
    var sets = group.sets
    if case let .process(pid) = group.id, grouping == .allAtOnce {
        let loose = sets.filter { if case .window = $0.id { return true }; return false }
        if let first = sets.firstIndex(where: { if case .window = $0.id { return true }; return false }) {
            var merged: [WindowSet] = []
            for (i, set) in sets.enumerated() {
                if i == first {
                    merged.append(WindowSet(.process(pid), loose.flatMap(\.windows)))
                } else if case .window = set.id {
                    continue
                } else {
                    merged.append(set)
                }
            }
            sets = merged
        }
    }
    var split: [WindowSet] = []
    for set in sets {
        let gone = set.windows.filter { minimized.contains($0) }
        guard !gone.isEmpty else {
            split.append(set)
            continue
        }
        let own = gone.map { WindowSet(.minimized($0), [$0]) }
        let rest = set.windows.filter { !minimized.contains($0) }
        if rest.isEmpty {
            split += own
        } else if minimized.contains(set.windows[0]) {
            split += own + [WindowSet(set.id, rest)]
        } else {
            split += [WindowSet(set.id, rest)] + own
        }
    }
    return ContainerGroup(group.id, split)
}

/// Strip order (R11, R12) from the strip candidates.
public func stripOrder(candidates: [GroupID], previous: StripState, replacementOrder: StripReplacementOrder,
                       maximumRowCount: Int) -> [GroupID] {
    guard replacementOrder == .stableLeastRecentlyUsed else { return candidates }
    var working = candidates
    if let stage = previous.stageGroup, let i = working.firstIndex(of: stage) {
        working.insert(working.remove(at: i), at: 0)
    }
    let previousPrefix = Array(previous.sortedStrip.prefix(maximumRowCount))
    let workingPrefix = Set(working.prefix(maximumRowCount))
    var result: [GroupID] = []
    for id in previousPrefix {
        guard result.count < maximumRowCount else { break }
        if workingPrefix.contains(id), let i = working.firstIndex(of: id) {
            // Keeps its slot.
            result.append(working.remove(at: i))
        } else if let i = working.firstIndex(where: { !previousPrefix.contains($0) }) {
            // Vacated: the group that left the stage first, else the next one not visible.
            result.append(working.remove(at: i))
        }
    }
    return result + working
}

/// The whole assignment (R1–R13).
public func assign(_ input: AssignmentInput) -> Assignment {
    let groups = containerGroups(zOrder: input.zOrder, userSets: input.userSets, minimized: input.minimized,
                                 hidden: input.hidden, grouping: input.grouping)
    // R7: the proposed window's group, else the first with a set not minimized. R8: none.
    var stage: ContainerGroup?
    if !input.emptyStage {
        stage = input.proposal.flatMap { p in groups.first { $0.windows.contains(p) } }
            ?? groups.first { $0.sets.contains { !$0.id.isMinimized } }
    }
    // R9.
    let stageSet = stage?.sets.first { !$0.id.isMinimized }
    // R10.
    var candidates = groups.map(\.id)
    if let stage, stage.sets.count == 1, !stage.sets[0].id.isMinimized {
        candidates.removeAll { $0 == stage.id }
    }
    // R11, R12, R13 (nothing is hidden here).
    let strip = stripOrder(candidates: candidates, previous: input.previous, replacementOrder: input.replacementOrder,
                           maximumRowCount: input.maximumRowCount)
    return Assignment(groups: groups, stageGroup: stage?.id, stageWindowSet: stageSet?.id, strip: strip)
}
