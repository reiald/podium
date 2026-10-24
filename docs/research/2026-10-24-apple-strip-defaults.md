# Apple's Stage Manager defaults

Source: macOS 27.2 (Darwin 27.2.0), `WindowManager.framework`, extracted from the dyld shared cache with
`ipsw dyld extract` and decompiled with REA (Ghidra 12.1.4). Observed, not inferred, unless marked.

- Settings: `WindowManagerPreferencesController.init` (`FUN_1d2af42c0`) gives every
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
  agent's `FUN_10030abfc`. At that rotation a 170 pt card would show about 44 pt wide, so it is
  probably not the strip's resting tilt (Inferred). `tiltRadians` and `perspectiveDistance` stay.
- Pile spacing (`LeftStripPileInterItemHorizontalSpacing` 16, `LeftStripPileVerticalSpacing` 30) and
  app icon offsets (left -10, bottom 10) have no matching Podium field yet.

## Strip layout (measured)

Screenshot of Apple's strip, macOS 27.2, 3008 × 1692 pt display, six items:

- Items are flat at rest, 16 pt from the screen edge (`LeftStripEdgeHorizontalInset`).
- Gaps between items: 30, 29, 30, 30 pt: `LeftStripPileVerticalSpacing` (30), not
  `InterItemVerticalSpacing` (32, which the agent never reads). Podium `rowSpacing` = 30.
- Every window is scaled by one shared factor (about 0.096 here: a near full-width window is
  290 × 150, System Settings 71 × 114), so small windows stay small. The agent's layout reads
  `MaximumItemHeight` 160, `PreferredMinimumItemHeight` 96 and `AbsoluteMinimumItemHeight` 20
  (`FUN_1002c125c`); 160 / 1662 pt matches the factor (Inferred).
- The stack is centered vertically.

Podium: `stripSlots(windowSizes:)` scales every window by `itemMaxSize.width / screen.width`,
capped to `itemMaxSize`; default `itemMaxSize` 290 × 160 (290 = Apple's widest item here).

## All decoded defaults

Booleans and hot keys show `?` (set from registers, not decoded).

```
LeftChameleonLeftBaseAlpha = 0.1
LeftChameleonLeftStepValue = 0.1
LeftChameleonRightBaseAlpha = 0.3
LeftChameleonRightStepValue = 0.1
LeftStripStackDepthStepValue = 0.1
LeftStripTiltLeftBaseAlpha = 0
LeftStripTiltLeftStepValue = 0
LeftStripTiltRightBaseAlpha = 0.1
LeftStripTiltRightStepValue = 0
StripCornerRadius = 8.0
StripHoverScaleDistance = 16.0
StripClickDownScaleDistance = 16.0
LeftStripAppIconBottomOffset = 10.0
LeftStripAppIconLeftOffset = -10.0
LeftStripAppIconTwoIconHorizontalSpacing = -4.0
LeftStripAppIconThreeIconHorizontalSpacing = -22.0
PilePerspectiveDistance = -1750.0
PilePerspectiveDistanceOverride = ?
PileShouldIgnoreHDR = ?
LeftStripEdgeHorizontalInset = 16.0
LeftStripPileInterItemHorizontalSpacing = 16.0
LeftStripPileVerticalSpacing = 30.0
LeftStripPileMaximumWindowCount = 3
PreferredMinimumItemHeight = 96.0
AbsoluteMinimumItemHeight = 20.0
MaximumItemHeight = 160.0
LeftStripMinimumRowCount = 4
LeftStripMaximumRowCount = 6
AppIconHoverScaleDistance = 5.0
CAContextPoolLimit = 5
ToggleStageManagerHotKey = 5.562684663752705e-309
EnableStageManagerHotKey = ?
ToggleAutohideHotKey = 3.89387925245241e-308
EnableAutohideHotKey = ?
ShiftClickToAddToSet = ?
ToggleSystemStickyHotKey = 2.503208091435829e-308
EnableSystemStickyHotKey = ?
ToggleAppStickyHotKey = 2.503208091759619e-308
EnableAppStickyHotKey = ?
TogglePromoteToSingleAppHotKey = 2.5032080914034493e-308
EnablePromoteToSingleAppHotKey = ?
MissionControlHotKey = 3.0594765569368937e-308
MissionControlAppIconSize = 48.0
ExposeSpringDampingRatio = 1.0
ExposeSpringResponse = 0.25
SpacesBarExitSpringResponse = 0.125
ExposeTrackpadVelocityThreshold = 5.0
ExposeTrackpadSpringResponseScale = 0.6
GeometricEpsilon = 1.0
ScalarEpsilon = 0.001
RotationEpsilon = 0.001
ColorEpsilon = 0.01
ProgressEpsilon = 0.01
EnableMissionControlHotKey = ?
StageManagerMinimizationBehavior = ?
InterItemVerticalSpacing = 32.0
InterItemHorizontalSpacing = 32.0
HorizontalInsetFromStrip = 16.0
VerticalInset = 0
StageFrameMinimumHorizontalInset = 4.0
ItemWidth = 170.0
ItemHeight = 170.0
LeftStripReplacementOrder = ?
AppIconSize = 40.0
AutoHideWhenOccluded = ?
AutoHideDelay = 0.15
EnableInlineAppExpose = ?
InlineAppExposeIconSize = 24.0
InlineAppExposeMaximumColumnCount = 3
InlineAppExposeStageMinimumHorizontalDistance = 80.0
InlineAppExposeStripEdgeHorizontalInset = 48.0
InlineAppExposeStripPileVerticalSpacing = 32.0
InlineAppExposeStripPileHorizontalSpacing = 48.0
InlineAppExposeMaximumItemHeight = 107.0
EnableStripCornerRadius = ?
EnableStrip3DTransform = ?
EnableStripSourceAtopBlending = ?
EnableStripMostlyOccludedFlag = ?
EnableStripShadows = ?
EnableStripShadowsRadiiScaling = ?
EnableStripShadowsInnerRimRadiusScaling = ?
EnableStripShadowsOuterRimRadiusScaling = ?
StripWindowShadowDensityMultiplier = 1.0
ShouldPersistLeftStripOrdering = ?
PileRotation = 75.0
AnimationSpeed = 1.0
SlowAnimationsWhileShiftHeld = ?
StripClickSessionTimeout = 1.25
HiddenStripPeekWidth = 0
EnableStageManagerClickToEmptyStage = ?
EnableStandardClickToShowDesktop = ?
```
