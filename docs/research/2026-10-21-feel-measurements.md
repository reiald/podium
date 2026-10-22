# Feel measurements: Apple Stage Manager vs Podium

Status: template. No measurements recorded yet. Tuning values in `Sources/PodiumCore/Layout/Tuning.swift` are still the placeholders from `Tuning.initial`.

## Purpose

Tune Podium's motion and layout to match Apple's Stage Manager by measuring frames from screen recordings of both, not by eyeballing. Every number recorded here maps to one `Tuning` field, so that a later change to `Tuning.initial` can be traced back to a measurement in this file.

## How to record

Record both Apple's Stage Manager and Podium the same way, so the clips are directly comparable.

- **Tool:** Cmd-Shift-5, then Record Selected Portion (or Record Entire Screen on the main display). Use the main display only.
- **Frame rate:** at least 60 fps. Check the actual value with `scripts/extract-frames.sh`, which prints the clip fps. If the recording is below 60 fps, re-record. Transition durations of about 0.4 s are only resolvable to 1-2 frames at 60 fps, so a higher rate is better.
- **Strip side:** put the strip on the LEFT for Podium so it is comparable with Apple's strip. If Apple's Stage Manager strip side is configurable, set it to the left and note it in the Notes column. If it is not configurable, record the side that Apple uses.
- **Scenarios** (one clip each, for both Apple and Podium):
  1. Switch stage: change from one stage to another.
  2. Minimize: minimize a window into the strip.
  3. Hover: move the pointer over a strip thumbnail and hold it there.
  4. Auto-hide: let the strip hide while no pointer is near it, then bring the pointer back to the edge.
  5. Peek: with the strip hidden, move the pointer to the edge so the peek sliver shows.
- **Naming:** keep the clip files outside the repository, and write the path next to each row in the clip log below.

### Clip log

| Scenario | Apple clip (path) | Podium clip (path) | Apple fps | Podium fps | Notes |
|---|---|---|---|---|---|
| Switch stage | | | | | |
| Minimize | | | | | |
| Hover | | | | | |
| Auto-hide | | | | | |
| Peek | | | | | |

## Extracting frames

```
scripts/extract-frames.sh <clip> <outdir>
```

The script refuses a non-empty `<outdir>`, prints the clip's fps and frame count, and writes `%04d.png` frames. Frame index times the frame period gives time: at 60 fps, frame N is at (N-1)/60 s after the first frame. Measure on the frames, then convert to time.

## How to measure each quantity

Work from the extracted frames. For each quantity, record the Apple value and the Podium value in the same units, in the table below.

- **Transition duration:** the first moving frame to the last moving frame (time between them). Use the frame where the first window edge moves and the frame where it stops. Record in seconds. Maps to `transitionSpring` (see the fitting note).
- **Overshoot:** yes or no, and how far the animated edge passes its final position, in points. Overshoot fraction = overshoot distance / total travel distance. Maps to `transitionSpring.dampingRatio` (see the fitting note).
- **Thumbnail size:** width and height of one strip thumbnail at rest, in points, measured on the window edges. Maps to `itemMaxSize`.
- **Slot spacing:** vertical distance between the tops of adjacent strip thumbnails, in points. Maps to `rowSpacing`.
- **Edge inset:** distance from the screen edge the strip sits at, in points. Maps to `stripEdgeInset`.
- **Tilt:** from the ratio of the far and near edge lengths of a tilted thumbnail, r = far / near. Under perspective with the item width w and perspective distance d, with the tilt θ about the vertical axis, s = (w/2) sin θ and r = (d - s) / (d + s), so θ = asin( 2d(1 - r) / (w(1 + r)) ). Check the sign convention against the renderer's perspective term before using the result. Maps to `tiltRadians` and `perspectiveDistance`; `perspectiveDistance` is in points and must be measured or assumed with the same convention.
- **Corner radius:** radius of a thumbnail's rounded corner, in points. Maps to `cornerRadius`.
- **Pile offsets:** for a pile of windows, the offset of each successive window from the front one (x and y, in points), and its scale relative to the front window. Maps to `pileStepOffset` and `pileStepScale`. Record the pile size as well, for `pileMaxWindows`.
- **Hover growth:** how many points the thumbnail grows on hover (the edge moves outward, measured from rest). Maps to `hoverScaleDistance`. Record the hover spring time in `hoverSpring` if it is visible.
- **Auto-hide delay:** time from the pointer leaving the strip to the start of the hide motion, in seconds. Maps to `autoHideDelay`.
- **Peek width:** width of the visible sliver when the strip is hidden, in points. Maps to `hiddenPeekWidth`.

### Measurement table

Fill one row per quantity. Leave a cell blank if it cannot be measured from the clips, and say why in Notes.

| Quantity | Apple | Podium | Tuning field | Notes |
|---|---|---|---|---|
| Transition duration (s) | | | `transitionSpring.response` (fitted) | |
| Overshoot (yes/no, points, fraction) | | | `transitionSpring.dampingRatio` (fitted) | |
| Thumbnail size (w x h, pt) | | | `itemMaxSize` | |
| Slot spacing (pt) | | | `rowSpacing` | |
| Edge inset (pt) | | | `stripEdgeInset` | |
| Tilt (edge ratio r, derived angle) | | | `tiltRadians`, `perspectiveDistance` | |
| Corner radius (pt) | | | `cornerRadius` | |
| Pile offset (x, y, pt) | | | `pileStepOffset` | |
| Pile scale per step | | | `pileStepScale` | |
| Pile size (windows) | | | `pileMaxWindows` | |
| Hover growth (pt) | | | `hoverScaleDistance` | |
| Auto-hide delay (s) | | | `autoHideDelay` | |
| Peek width (pt) | | | `hiddenPeekWidth` | |

`Tuning` fields not covered by a brief quantity, and so not measured in this pass: `maxRowCount`, `perspectiveDistance` (only as an input to tilt), `appIconSize`, `clickDownScaleDistance`, `autoHideOverlapThreshold`, `stageInset`, `hoverSpring`. Leave them at their current values unless a later measurement covers them.

## Fitting `response` and `dampingRatio`

`Spring(response:dampingRatio:)` uses ω = 2π / response for the natural frequency, and ζ = dampingRatio.

1. Overshoot fraction os from the measured overshoot (overshoot distance / travel distance). For example, 5% overshoot is os = 0.05.
2. Damping ratio from the overshoot, using ζ = -ln(os) / sqrt(π² + ln(os)²). For os = 0.05, ζ is about 0.69. If there is no overshoot, the spring is critically or over-damped and ζ is at least 1; use a value of 1.0 and say so in Notes.
3. Settle time for a 2% envelope: T_settle ≈ 4 / (ζω). Substituting ω = 2π / response gives response = π ζ T_settle / 2.
4. Measured transition duration: use the first-to-last moving frame interval from the table as T_settle. It is an approximation: it assumes the motion stops being visible at the 2% envelope, so re-check the fitted response against the clip by replaying the spring in the frame diff.

Worked example (not a measurement): ζ = 0.86 and response = 0.42 s give ω = 14.96 rad/s and T_settle ≈ 4 / (0.86 x 14.96) ≈ 0.31 s.

## Acceptance checklist (Step 5)

The owner fills in Pass or Fail for each item after comparing the clips.

| Item | Criterion | Pass | Fail | Notes |
|---|---|---|---|---|
| No visible blink at the swap | No single-frame flash, gap or flicker when a window swaps between stage and strip, checked frame by frame in the Podium clip | | | |
| Timing | Podium transition duration within about 10% of Apple's for each scenario | | | |
| Click-to-motion latency | Under about 50 ms: from the frame where the click lands to the first moving frame in the Podium clip | | | |
| No dropped frames at 120 Hz | No dropped frames at 120 Hz, from the Task 11 log | | | |
| Indistinguishable side by side | The owner cannot reliably tell the Podium and Apple clips apart when shown side by side | | | |

## Status

- Step 2 (frame extraction script): done, `scripts/extract-frames.sh`.
- Step 3 (measure Apple's clips): not started. Waiting on the owner's recordings.
- Step 4 (update `Tuning.initial`, add `tuningMatchesMeasurements`): not started. Depends on Step 3.
- Step 5 (acceptance): not started.
