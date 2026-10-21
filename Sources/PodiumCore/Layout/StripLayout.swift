import CoreGraphics
import Foundation

public struct StripSlot: Equatable, Sendable {
    public let stageID: UUID
    public let frame: CGRect
    public let tiltRadians: CGFloat
}

// All geometry is computed for the strip on the RIGHT, then passed through `oriented`,
// the single side-dependent x-transform (a reflection about the screen's vertical midline).

private func oriented(_ rect: CGRect, in screen: CGRect, side: StripSide) -> CGRect {
    guard side == .left else { return rect }
    return CGRect(x: screen.minX + screen.maxX - rect.maxX, y: rect.minY,
                  width: rect.width, height: rect.height)
}

/// +1 for `.left`, -1 for `.right`: how x-direction quantities flip with the side.
private func xSign(_ side: StripSide) -> CGFloat { side == .left ? 1 : -1 }

private func bandWidth(_ tuning: Tuning) -> CGFloat {
    tuning.stripEdgeInset + tuning.itemMaxSize.width + tuning.stripEdgeInset
}

public func stripBand(in screen: CGRect, side: StripSide, tuning: Tuning) -> CGRect {
    let w = bandWidth(tuning)
    let rightBand = CGRect(x: screen.maxX - w, y: screen.minY, width: w, height: screen.height)
    return oriented(rightBand, in: screen, side: side)
}

public func stageArea(in screen: CGRect, side: StripSide, tuning: Tuning) -> CGRect {
    let w = bandWidth(tuning) + tuning.stageInset
    let rightArea = CGRect(x: screen.minX, y: screen.minY, width: screen.width - w, height: screen.height)
    return oriented(rightArea, in: screen, side: side)
}

/// `stages` must already be most-recently-used first; only the first `maxRowCount` get slots.
public func stripSlots(for stages: [Stage], in screen: CGRect, side: StripSide, tuning: Tuning) -> [StripSlot] {
    let shown = stages.prefix(tuning.maxRowCount)
    guard !shown.isEmpty else { return [] }
    let size = tuning.itemMaxSize
    let total = CGFloat(shown.count) * size.height + CGFloat(shown.count - 1) * tuning.rowSpacing
    let top = screen.midY - total / 2
    let x = screen.maxX - tuning.stripEdgeInset - size.width
    return shown.enumerated().map { index, stage in
        let y = top + CGFloat(index) * (size.height + tuning.rowSpacing)
        let frame = oriented(CGRect(origin: CGPoint(x: x, y: y), size: size), in: screen, side: side)
        return StripSlot(stageID: stage.id, frame: frame, tiltRadians: xSign(side) * tuning.tiltRadians)
    }
}

/// Front window first. Offset x is mirrored by side via `xSign` (negated for `.right`).
public func pileOffsets(windowCount: Int, side: StripSide, tuning: Tuning) -> [(offset: CGSize, scale: CGFloat)] {
    let count = min(max(windowCount, 0), tuning.pileMaxWindows)
    return (0..<count).map { i in
        let step = CGFloat(i)
        return (offset: CGSize(width: xSign(side) * tuning.pileStepOffset.width * step,
                               height: tuning.pileStepOffset.height * step),
                scale: pow(tuning.pileStepScale, step))
    }
}

/// Top-left at the display's bottom-right corner minus 1pt, so exactly a 1x1 point stays on screen.
public func parkingOrigin(for windowSize: CGSize, display: CGRect) -> CGPoint {
    CGPoint(x: display.maxX - 1, y: display.maxY - 1)
}
