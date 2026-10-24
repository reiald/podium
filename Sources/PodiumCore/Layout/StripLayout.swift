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

/// Where a window dragged by its title bar drops into the strip: the band without its outer
/// `stripEdgeInset` margin. A drag that ends at the screen edge is macOS tiling the window
/// (Fill & Arrange), not a drop.
public func stripDropBand(in screen: CGRect, side: StripSide, tuning: Tuning) -> CGRect {
    let band = stripBand(in: screen, side: .right, tuning: tuning)
    let inner = CGRect(x: band.minX, y: band.minY, width: band.width - tuning.stripEdgeInset, height: band.height)
    return oriented(inner, in: screen, side: side)
}

public func stageArea(in screen: CGRect, side: StripSide, tuning: Tuning) -> CGRect {
    let w = bandWidth(tuning) + tuning.stageInset
    let rightArea = CGRect(x: screen.minX, y: screen.minY, width: screen.width - w, height: screen.height)
    return oriented(rightArea, in: screen, side: side)
}

/// `stages` must already be in strip order; only the first `maxRowCount` get slots.
///
/// As in Apple's strip, every item is its front window (`windowSizes`, by stage id) scaled by
/// one shared factor, so a full-width window is `itemMaxSize.width` wide and smaller windows
/// stay smaller; an item never exceeds `itemMaxSize`. With `uniformItemSize`, every item
/// fills the box instead. Slots hug the screen edge, stack `rowSpacing` apart, and the stack
/// is centered. A stage without a known size gets the box.
public func stripSlots(for stages: [Stage], in screen: CGRect, side: StripSide, tuning: Tuning,
                       windowSizes: [UUID: CGSize] = [:]) -> [StripSlot] {
    let shown = stages.prefix(tuning.maxRowCount)
    guard !shown.isEmpty else { return [] }
    let box = tuning.itemMaxSize
    let scale = box.width / screen.width
    let sizes = shown.map { stage -> CGSize in
        guard let window = windowSizes[stage.id], window.width > 0, window.height > 0 else { return box }
        let boxFit = min(box.width / window.width, box.height / window.height)
        let fit = tuning.uniformItemSize ? boxFit : min(scale, boxFit)
        return CGSize(width: window.width * fit, height: window.height * fit)
    }
    let total = sizes.reduce(0) { $0 + $1.height } + CGFloat(shown.count - 1) * tuning.rowSpacing
    var y = screen.midY - total / 2
    return zip(shown, sizes).map { stage, size in
        let x = screen.maxX - tuning.stripEdgeInset - size.width
        let frame = oriented(CGRect(origin: CGPoint(x: x, y: y), size: size), in: screen, side: side)
        y += size.height + tuning.rowSpacing
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
