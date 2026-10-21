# How Apple's Stage Manager works (macOS 27.2, build 26B118)

Static reading of shipped binaries only: import tables, exported symbols, strings, entitlements. Nothing was decompiled or run. **Observed** = seen directly in the binary. **Inferred** = a reasonable reading of what was seen.

Binary: `/System/Library/CoreServices/WindowManager.app/Contents/MacOS/WindowManager` (Swift module `WindowManagerAgent`, sha256 `35f57fc7…418b`). Launched on demand by launchd as `com.apple.WindowManager.agent` and serves `com.apple.windowmanager.server`, `.external`, `.dragserver`.

## 1. It moves the real windows, not pictures (observed)

It imports about 285 private window-server (SkyLight/CGS) functions, including:

- `SLSTransactionSetWindowTransform3D`, `SLSTransactionSetWindowTransform`, `CGSSetWindowTransformAtPlacement`: tilt and shrink a real window into a strip thumbnail.
- `SLSTransactionSetWindowAlpha` / `SetWindowSystemAlpha`, `SetWindowSystemCornerRadius`, `SetWindowShadowProperties`, `SetWindowWarp`: fade, round and shadow the real window.
- `SLSTransactionSetWindowIsActiveOffscreen`: keep a window drawing while it's off stage, which is how thumbnails stay live.
- `SLSTransactionSetWindowLockedBounds`: stop an app from moving its own window during a transition.
- `SLSTransactionCreate` / `SLSTransactionCommit`: batch all of these into one atomic update, so every window changes in the same frame.

The entitlement `com.apple.private.skylight.windowmanager` is what lets it do this to other apps' windows. Third-party apps can't get it.

**For Podium:** this is the gap we can't close with Apple's method. Podium has to use snapshots and live captures for the strip and swap them with the real window at the right moment, which the design already plans. Apple's version never swaps anything, so it never risks a blink. Podium has to earn "no blink" through careful timing.

## 2. Minimize to strip is a request from the app itself (observed + inferred)

- Every app's AppKit links `WindowManagement.framework`, which contains `WMClientWindowManager`, the client side (observed).
- WindowManager has `AppKitApplicationConnection`, `MiniaturizeWindowsRequest/Response`, `windowMiniaturizationResponse:` and `StageManagerMiniaturizeWindowTransitionModifier` (observed).
- Inferred flow: when you click the yellow button, AppKit asks Stage Manager to handle the minimize instead of playing the Dock's genie. Stage Manager answers and runs its own transition.
- Podium can't take the place of that service: the service name belongs to Apple's launchd job, and the client is built into AppKit.

**For Podium:** the design's plan holds. Catch the minimize click or Cmd-M first, with the "un-minimize, then park" fallback.

## 3. Motion: interruptible, velocity-preserving springs (observed names, inferred behavior)

Types seen: `SpringAnimation`, `SpringBehavior`, `SpringAnimationStyle`, `_C2SpringIntegration`, `initialVelocity`, `alphaInitialVelocity`, `VelocityFilter2D`, `cachedVelocity`, `mouseVelocity`.

Inferred: every animated value is driven by a physics spring that keeps its current speed when retargeted. If you click again mid-animation, the motion bends toward the new target instead of restarting. Pointer and gesture velocity feeds into it.

**For Podium:** this is probably the main reason the spike felt "smooth, but not Apple smooth." The spike's Core Animation springs restart from the current position at zero velocity. Podium should run its own spring engine (per-frame, `CADisplayLink`-driven, carrying velocity across retargets) and expose response and damping as tuning values.

## 4. Architecture: components plus transition modifiers (observed names)

There are about 60 `…Component` types (for example `StageManagerStripComponent`, `StageCalculatorComponent`, `StageManagerAutoHideComponent`, `StageManagerMiniaturizedWindowsComponent`, `StageManagerWindowGroupComponent`, `StageManagerAvailableFrameComponent`) and many `…TransitionModifier` types (for example `StageManagerStripStageTransitionModifier`, `StageManagerAutoHideTransitionModifier`, `StageManagerMiniaturizeWindowTransitionModifier`, `StageManagerStripPeekTransitionModifier`, `StageManagerToggleTransitionModifier`).

Inferred: a model holds the stages and windows. Components compute layout from that model (where the strip goes, how big the stage area is). A transition is a modifier that animates from one layout to the next, and each frame is committed as one window-server transaction.

**For Podium:** a clean model to copy. Keep one source of truth (the stages and windows), pure layout functions that turn it into target frames, and transitions that animate between layouts. It also makes left/right a single input to the layout, and makes the window-safety record easy.

## 5. Auto-hide, hover and layout tuning (observed)

- Auto-hide: `HidesWhenOccludedParameters`, `OcclusionTrackingTargetModel`, and the preferences `autoHide`, `autoHideDelay`, `autoHideOverlapThreshold`, `autoHideWhenOccluded`, `hiddenStripPeekWidth`. Inferred: the strip hides when stage windows cover more than a threshold share of the strip area, after a delay, and leaves a thin "peek" width at the edge.
- Hover: `HoverGestureRecognizer`, `HoverLatchingTarget`, and the preferences `stripHoverScaleDistance` and `stripClickDownScaleDistance`. Inferred: hover and click-down scale by a distance in points, not a percentage, and hover "latches" so it doesn't flicker between neighbors.
- Layout preferences: `leftStripMaximumRowCount`, `leftStripMinimumRowCount`, `leftStripPileMaximumWindowCount`, `leftStripPileVerticalSpacing`, `leftStripPileInterItemHorizontalSpacing`, `leftStripTiltLeft/RightBaseAlpha`, `leftStripStackDepthStepValue`, `pileRotation`, `pilePerspectiveDistance`, `stripCornerRadius`, `stripWindowShadowDensityMultiplier`, `appIconSize`, `maximumItemHeight`, `preferredMinimumItemHeight`, `horizontalInsetFromStrip`, `stageFrameMinimumHorizontalInset`, `animationSpeed`. Note that every one of these says "leftStrip": Apple only designed for the left side, and the right side is a mirror.

The actual numbers are compiled into code and weren't read. They come from measuring screen recordings (design decision) or, later, from decompiling.

## 6. Where it learns the strip side (observed, from earlier)

The Dock calls `setDockInfoWithDisplayID:currentInset:maximumInset:orientation:` on Stage Manager. That's the only input for side, and it's gated by entitlements.

## Still unknown

- The exact spring response, damping and timing values.
- Whether third-party apps that don't use AppKit (Electron, Java) also route minimize through this service.
- How Stage Manager hides off-stage windows: whether it fades them, moves them to a private space (it imports `CGSSpaceCreate` and `SLSTransactionSetSpaceAlpha`/`Transform`), or both.
- **Do parked windows keep producing live ScreenCaptureKit frames?** (Task 10's early risk; not yet run.) Podium parks a window by moving all but a 1x1 pt corner off screen. Whether `SCStream` with `SCContentFilter(desktopIndependentWindow:)` still delivers new frames for such a window decides whether the strip can show live thumbnails of off-stage windows.

  How to answer it (needs Screen Recording and Accessibility granted to `build/Podium.app`; the first run may only show the Screen Recording prompt, so grant it and run again):

  ```sh
  open -a TextEdit && osascript -e 'tell application "TextEdit" to make new document'
  PODIUM_SIGN_IDENTITY=- scripts/build-app.sh
  pkill -x Podium; open build/Podium.app --args --debug-capture-parked com.apple.TextEdit
  # Within the 30 s window, type into the parked document:
  for i in $(seq 1 20); do osascript -e 'tell application "TextEdit" to set text of front document to (text of front document) & "podium "'; sleep 1; done
  log show --last 2m --style compact --predicate 'process == "Podium"' | grep 'debug capture'
  ```

  Reading the log: `on-stage snapshot ... ok` shows capture works at all. Then each `frame N t=... dt=... content=changed|same|first` line is one new frame; ScreenCaptureKit only sends a frame when the window's content changes, so with the typing loop running, steady lines about 1 s apart with `content=changed` mean **yes, parked windows stream live**. Only a `first` frame (or none) while the loop types means **no**. The run ends with `done; frames=N distinct=M changes=K; unpark ok`: K close to the number of edits is yes, K = 0 is no.

  Decision either way (no code rewrite needed): if yes, keep `Capture.liveCapturesParkedWindows = true` (the default). If no, set it to false (`await capture.setLiveCapturesParkedWindows(false)`); the strip then shows the last snapshot taken while the window was on stage, which the Coordinator refreshes once per second for every on-stage window.
