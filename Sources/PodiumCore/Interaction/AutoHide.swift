import CoreGraphics
import Foundation

/// Decides when the strip slides away (windows cover it) and peeks back (pointer at the strip-side edge).
public struct AutoHide: Sendable {
    public private(set) var isHidden = false
    private let tuning: Tuning
    private var outsideSince: TimeInterval?

    public init(tuning: Tuning) {
        self.tuning = tuning
    }

    public mutating func update(overlapFraction: Double, pointer: CGPoint, band: CGRect,
                                screen: CGRect, side: StripSide, now: TimeInterval) {
        let inBand = band.contains(pointer)

        if isHidden {
            let atEdge = side == .right
                ? pointer.x >= screen.maxX - tuning.hiddenPeekWidth
                : pointer.x <= screen.minX + tuning.hiddenPeekWidth
            guard atEdge else { return }
            isHidden = false
            outsideSince = inBand ? nil : now
            return
        }

        guard overlapFraction > Double(tuning.autoHideOverlapThreshold), !inBand else {
            outsideSince = nil
            return
        }
        let since = outsideSince ?? now
        outsideSince = since
        if now - since >= tuning.autoHideDelay { isHidden = true }
    }
}
