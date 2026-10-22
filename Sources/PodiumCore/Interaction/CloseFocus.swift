/// When a window closes or an app quits, macOS focuses another window on its own: the app's
/// next window, or the next app's. Stage Manager doesn't follow that focus to a window off
/// stage; the stage stays as the close left it (empty means the desktop). Focus the user asks
/// for (a click, Cmd-Tab) comes later than `quiet`.
public struct CloseFocus: Sendable {
    public static let quiet: Double = 0.75
    private var lastClose = -Double.infinity

    public init() {}

    public mutating func closed(at t: Double) { lastClose = t }

    /// Focusing `w` at `t` is the system's doing after a close and would bring a window from
    /// the strip on stage.
    public func ignores(_ w: WindowRef, at t: Double, board: StageBoard) -> Bool {
        t - lastClose < Self.quiet && isOffStage(w, board)
    }

    /// The same for an app activation: the app has nothing on stage but windows in the strip.
    public func ignores(appActivated pid: Int32, at t: Double, board: StageBoard) -> Bool {
        guard t - lastClose < Self.quiet else { return false }
        let windows = board.stages.flatMap(\.windows).filter { $0.pid == pid }
        return !windows.isEmpty && windows.allSatisfy { isOffStage($0, board) }
    }

    private func isOffStage(_ w: WindowRef, _ board: StageBoard) -> Bool {
        board.stages.contains { $0.windows.contains(w) }
            && board.activeStage?.windows.contains(w) != true
            && !board.isMinimized(w)
    }
}
