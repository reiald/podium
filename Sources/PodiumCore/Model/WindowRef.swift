/// Identifies one on-screen window: owning process plus its window ID.
public struct WindowRef: Hashable, Codable, Sendable {
    public let pid: Int32
    public let windowID: UInt32

    public init(pid: Int32, windowID: UInt32) {
        self.pid = pid
        self.windowID = windowID
    }
}
