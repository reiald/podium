import Foundation

/// What a model change means on screen.
///
/// - `leaving`: windows of the old active stage that are no longer in the active stage but
///   still on the board (they fly into the strip). Closed windows never leave.
/// - `entering`: windows of the new active stage that were in a non-active stage before
///   (they fly out of the strip). Windows new to the board never enter: they are already
///   on screen.
/// - `stripOrder`: the new board's strip stages, in strip order.
///
/// Both lists keep the new board's (most-recently-focused) window order.
public struct TransitionPlan: Equatable, Sendable {
    public var leaving: [WindowRef]
    public var entering: [WindowRef]
    public var stripOrder: [UUID]

    public init(leaving: [WindowRef], entering: [WindowRef], stripOrder: [UUID]) {
        self.leaving = leaving
        self.entering = entering
        self.stripOrder = stripOrder
    }
}

public func transitionPlan(from old: StageBoard, to new: StageBoard) -> TransitionPlan {
    let oldActive = Set(old.activeStage?.windows ?? [])
    let newActive = new.activeStage?.windows ?? []
    let newActiveSet = Set(newActive)
    let oldOnBoard = Set(old.stages.flatMap(\.windows))

    let leaving = new.stages.flatMap(\.windows).filter { oldActive.contains($0) && !newActiveSet.contains($0) }
    let entering = newActive.filter { oldOnBoard.contains($0) && !oldActive.contains($0) }
    return TransitionPlan(leaving: leaving, entering: entering, stripOrder: new.stripStages.map(\.id))
}
