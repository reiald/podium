import Combine
import Foundation
import PodiumCore

/// User settings, persisted in `UserDefaults` as they change.
@MainActor
final class Settings: ObservableObject {
    private let defaults: UserDefaults

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var side: StripSide { didSet { defaults.set(side.rawValue, forKey: "side") } }
    @Published var minimizeBehavior: MinimizeBehavior {
        didSet { defaults.set(minimizeBehavior.rawValue, forKey: "minimizeBehavior") }
    }
    @Published var autoHide: Bool { didSet { defaults.set(autoHide, forKey: "autoHide") } }
    /// The onboarding window was completed once.
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    /// Podium turned Apple's Stage Manager off (so the menu offers to turn it back on).
    @Published var turnedOffAppleStageManager: Bool {
        didSet { defaults.set(turnedOffAppleStageManager, forKey: "turnedOffAppleStageManager") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        side = defaults.string(forKey: "side").flatMap(StripSide.init(rawValue:)) ?? .right
        minimizeBehavior = defaults.string(forKey: "minimizeBehavior").flatMap(MinimizeBehavior.init(rawValue:)) ?? .strip
        autoHide = defaults.object(forKey: "autoHide") as? Bool ?? true
        onboarded = defaults.bool(forKey: "onboarded")
        turnedOffAppleStageManager = defaults.bool(forKey: "turnedOffAppleStageManager")
    }
}
