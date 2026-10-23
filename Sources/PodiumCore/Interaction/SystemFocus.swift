/// Focus the system moves on its own, which must not pull a window off the strip:
///
/// - When a window closes or an app quits, macOS focuses another window: the app's next
///   window, or the next app's. The stage stays as the close left it (empty: the desktop).
/// - After a strip click Podium activates the chosen stage's app, and the app reports its own
///   key window as focused, which may be one of its windows in another strip stage.
///
/// Stage Manager doesn't follow either to a window off stage. Focus the user asks for (a
/// click, Cmd-Tab) comes later than `quiet`.
public struct SystemFocus: Sendable {
    public static let quiet: Double = 0.75
    private var since = -Double.infinity

    public init() {}

    public mutating func closed(at t: Double) { since = t }

    /// Podium put a stage on stage the user chose (a strip click, the app view).
    public mutating func stageChosen(at t: Double) { since = t }

    /// Focusing `w` at `t` is the system's doing and would bring a window from
    /// the strip on stage.
    public func ignores(_ w: WindowRef, at t: Double, board: StageBoard) -> Bool {
        t - since < Self.quiet && isOffStage(w, board)
    }

    /// The same for an app activation: the app has nothing on stage but windows in the strip.
    public func ignores(appActivated pid: Int32, at t: Double, board: StageBoard) -> Bool {
        guard t - since < Self.quiet else { return false }
        let windows = board.stages.flatMap(\.windows).filter { $0.pid == pid }
        return !windows.isEmpty && windows.allSatisfy { isOffStage($0, board) }
    }

    private func isOffStage(_ w: WindowRef, _ board: StageBoard) -> Bool {
        board.stages.contains { $0.windows.contains(w) }
            && board.activeStage?.windows.contains(w) != true
            && !board.isMinimized(w)
    }
}
