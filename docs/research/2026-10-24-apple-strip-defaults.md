# Apple's Stage Manager defaults

Source: macOS 27.2, the setting defaults in `WindowManager.framework`. Observed, not inferred, unless marked. Function addresses and decompiled code are intentionally left out.

- Settings: `WindowManagerPreferencesController.init` gives every
  `InternalSetting` its name and default. The names are also `com.apple.WindowManager` defaults keys.
- Springs: `WindowManagerSpringBehavior.defaultPosition` uses `defaultPositionResponse` 0.38 and
  `defaultDampingRatio` 1.0; `defaultAlpha` uses `defaultAlphaResponse` 0.3; initial velocity 0.

## What Podium uses

| Apple setting | Apple | Podium `Tuning` | Podium before |
|---|---|---|---|
| defaultPosition spring | response 0.38, damping 1.0 | `transitionSpring` | 0.32, 0.9 |
| LeftStripEdgeHorizontalInset | 16 | `stripEdgeInset` | 16 |
| LeftStripMaximumRowCount | 6 | `maxRowCount` | 6 |
| LeftStripPileMaximumWindowCount | 3 | `pileMaxWindows` | 3 |
| StripCornerRadius | 8 | `cornerRadius` | 12 |
| AppIconSize | 40 | `appIconSize` | 28 |
| StripHoverScaleDistance | 16 | `hoverScaleDistance` | 8 |
| StripClickDownScaleDistance | 16 | `clickDownScaleDistance` | 4 |
| AutoHideDelay | 0.15 | `autoHideDelay` | 0.25 |

Not adopted:
- `HiddenStripPeekWidth` is 0, but Podium's `hiddenPeekWidth` is the reveal zone, which Apple sets
  separately (`StageManagerStripShowRegionEdgePadding`, default not decoded). It stays 6.
- `PileRotation` 75 (degrees, sign by strip side) with `PilePerspectiveDistance` -1750: used in the
  pile view. At that rotation a 170 pt card would show about 44 pt wide, so it is
  probably not the strip's resting tilt (Inferred). `tiltRadians` and `perspectiveDistance` stay.
- Pile spacing (`LeftStripPileInterItemHorizontalSpacing` 16, `LeftStripPileVerticalSpacing` 30) and
  app icon offsets (left -10, bottom 10) have no matching Podium field yet.

## Strip layout (measured)

Screenshot of Apple's strip, macOS 27.2, 3008 × 1692 pt display, six items:

- Items are flat at rest, 16 pt from the screen edge (`LeftStripEdgeHorizontalInset`).
- Gaps between items: 30, 29, 30, 30 pt: `LeftStripPileVerticalSpacing` (30), not
  `InterItemVerticalSpacing` (32, which the strip's layout never reads). Podium `rowSpacing` = 30.
- Every window is scaled by one shared factor (about 0.096 here: a near full-width window is
  290 × 150, System Settings 71 × 114), so small windows stay small. The strip's layout reads
  `MaximumItemHeight` 160, `PreferredMinimumItemHeight` 96 and `AbsoluteMinimumItemHeight` 20; 160 / 1662 pt matches the factor (Inferred).
- The stack is centered vertically.

Podium: `stripSlots(windowSizes:)` scales every window by `itemMaxSize.width / screen.width`,
capped to `itemMaxSize`; default `itemMaxSize` 290 × 160 (290 = Apple's widest item here).
