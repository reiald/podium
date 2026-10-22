import Foundation

/// The strip's app view (an app icon was clicked): one virtual single-window stage per
/// window of `pid` that is off stage (not on the active stage, not in the Dock), most
/// recently focused first. Windows never focused keep their strip order.
///
/// Each item's id comes from `appWindowItemID`, so it is the same across relayouts and
/// never equals a real stage's id.
public func appWindowItems(board: StageBoard, pid: Int32) -> [Stage] {
    let windows = board.stripStages.flatMap(\.windows).filter { $0.pid == pid && !board.isMinimized($0) }
    return windows.enumerated()
        .sorted { a, b in
            let (fa, fb) = (board.lastFocus(of: a.element), board.lastFocus(of: b.element))
            return fa != fb ? fa > fb : a.offset < b.offset
        }
        .map { Stage(id: appWindowItemID($0.element), windows: [$0.element]) }
}

/// A UUID made of the window's id and pid, with version nibble 8: real stage ids are
/// random version 4 UUIDs, so the two can never collide.
public func appWindowItemID(_ w: WindowRef) -> UUID {
    let id = w.windowID, pid = UInt32(bitPattern: w.pid)
    func byte(_ v: UInt32, _ shift: UInt32) -> UInt8 { UInt8(truncatingIfNeeded: v >> shift) }
    return UUID(uuid: (byte(id, 24), byte(id, 16), byte(id, 8), byte(id, 0),
                       0, 0, 0x80, 0, 0x80, 0, 0, 0,
                       byte(pid, 24), byte(pid, 16), byte(pid, 8), byte(pid, 0)))
}
