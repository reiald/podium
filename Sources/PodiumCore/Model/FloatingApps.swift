/// Apps whose windows float over the stage instead of getting one (Settings): Podium never
/// manages them, so opening or closing one leaves the stage as it is.
public struct FloatingApps: Equatable, Sendable {
    public var enabled: Bool
    public var bundleIDs: [String]

    public static let defaults = FloatingApps(
        enabled: true, bundleIDs: ["com.apple.archiveutility", "com.interversehq.qView", "com.apple.Preview"])

    public init(enabled: Bool, bundleIDs: [String]) {
        self.enabled = enabled
        self.bundleIDs = bundleIDs
    }

    public func floats(_ bundleID: String?) -> Bool {
        guard enabled, let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }

    public mutating func add(_ bundleID: String) {
        if !bundleIDs.contains(bundleID) { bundleIDs.append(bundleID) }
    }

    public mutating func remove(_ bundleID: String) {
        bundleIDs.removeAll { $0 == bundleID }
    }
}
