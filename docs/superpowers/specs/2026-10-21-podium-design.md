# Podium — Design

Date: 2026-10-21
Status: draft, awaiting owner approval

## What it is and why

Podium is a standalone macOS app that replaces Apple's Stage Manager with one that looks and behaves like Apple made it, but can be customized. The first customization, and the reason the project exists, is **choosing which side of the screen the strip sits on** (left or right) without moving the Dock.

The owner wants Podium to be open source on GitHub and to grow into a home for many more Stage Manager tweaks later. Version 1 is about the core experience being right; the extra customizations come after.

### What we learned before designing (keep this; it rules out tempting dead ends)

Investigated on macOS 27.2 (build 26B118) by reading Apple's binaries:

- Stage Manager lives in `/System/Library/CoreServices/WindowManager.app` plus the private `WindowManager.framework`.
- It has **no setting for the strip's side**. Every preference it reads was listed; none controls side.
- The **Dock decides the side**: Dock calls `setDockInfoWithDisplayID:currentInset:maximumInset:orientation:` on Stage Manager, per display. Stage Manager places the strip opposite the Dock.
- That channel is protected by Apple-only entitlements. Spoofing it, or patching Stage Manager, requires turning off System Integrity Protection (SIP).
- Stage Manager's smoothness comes partly from private window-server entitlements (`com.apple.private.skylight.windowmanager`) that let it transform other apps' windows directly. Third-party apps cannot get these.

Rejected approaches and why:

| Approach | Rejected because |
|---|---|
| Hidden preference | Doesn't exist |
| Patch/inject into Stage Manager or Dock | Requires users to disable SIP; owner wants zero hassle for anyone |
| Move real Dock left and hide it, draw a fake Dock at the bottom | Means building and maintaining a Dock clone; owner called it patchwork and unsustainable |

**Chosen approach:** Podium is its own Stage Manager. The user turns Apple's off. Podium uses only public APIs plus at most small, widely used, SIP-free private calls (e.g. `_AXUIElementGetWindow`, already used by AltTab, Rectangle and others).

### Spike result

A throwaway spike (`spikes/fly-to-strip/`) proved the core trick: snapshot a window with ScreenCaptureKit, show the snapshot in an overlay exactly over the real window, move the real window off-screen via Accessibility, then animate the snapshot into a tilted thumbnail in a right-side strip. The owner tried it: "good and smooth but not Apple Stage Manager level smooth yet." Unpark-on-click didn't work in the spike, and it had no hover or auto-hide. The spike code is reference only; v1 is a fresh build.

## Who it's for

Anyone on a Mac who likes Stage Manager but wants it on the other side, or wants to tweak it. Install should be: download, open, grant two permissions, done. No Terminal, no Recovery Mode, no SIP.

## Goals (v1)

1. **Feels Apple-made.** Motion, timing, tilt, shadows, corner radii, hover, and auto-hide should be hard to tell apart from Apple's Stage Manager. This is the bar the owner cares about most.
2. **Strip side is a setting**: left or right.
3. **Core Stage Manager behavior** (matching Apple):
   - One stage (a group of windows) is on screen at a time; other stages show as thumbnails in the strip.
   - Click a thumbnail: that stage comes to center, and the current stage goes to the strip (a swap).
   - Switching to an app another way (Cmd-Tab, Dock click, clicking a notification) brings that app's stage forward.
   - New windows join the current stage (Apple's default behavior).
   - Each strip item shows a small pile of that stage's windows (up to ~3, stacked/tilted) with the app icon.
   - **Live thumbnails** that update while parked.
   - **Hover**: thumbnail grows slightly under the pointer.
   - **Auto-hide**: when a stage window overlaps the strip area, the strip slides away; it peeks back when the pointer reaches that screen edge.
   - **Minimize goes to the strip, not the Dock** (owner specifically called this out as "so smooth" in Apple's). Clicking the yellow button or pressing Cmd-M should fly the window into the strip with Podium's animation instead of the Dock's genie effect. Likely approach (to prove early): watch mouse-down/Cmd-M via an event tap, use Accessibility hit-testing to recognize the minimize button, swallow the event, and park the window instead. Reacting after the fact (un-minimizing on the minimized notification) would show the genie first and is not acceptable. Apple has a matching preference, `StageManagerMinimizationBehavior`, with a `dock` option, so Podium should offer "minimize to strip / to Dock" as a setting.
4. **Never lose a window.** Quitting, crashing, or being force-quit must not strand windows off-screen. Parked windows are recorded on disk; on next launch Podium restores any stranded ones. Quit restores all.
5. **Menu bar item** with: on/off, strip side, a few basic options, Settings window, Quit.
6. **Detects Apple's Stage Manager** being on and offers to turn it off (or explains how).

## Non-goals (v1)

- Top/bottom strip positions (later customization).
- Recreating Mission Control, Spaces management, or the Dock.
- Anything requiring SIP changes or kernel/system extensions.
- Mac App Store distribution (Accessibility-driven window managers can't ship there; GitHub releases instead).
- Rich theming, per-app rules, keyboard-shortcut system beyond basics. These are the "10x customization" phase, after v1 feels right.

## Anti-goals (fail even if it technically works)

- Visible blink or jump when a real window swaps with its snapshot.
- Windows ending up lost off-screen.
- Any setup step beyond granting Accessibility and Screen Recording.
- Laggy feel: perceptible pause between click and motion start.
- A patchwork feel: Podium must not look like a third-party bolt-on.

## Constraints

- Platform: macOS. Owner is on macOS 27.2, Apple Silicon. Minimum supported version is the builder's call, but ScreenCaptureKit screenshot APIs need macOS 14+.
- Language/stack: Swift, AppKit, Core Animation for the strip and transitions (owner wants Apple-native feel; my call). SwiftUI is fine for the Settings window.
- Permissions: Accessibility (move/hide/raise windows) and Screen Recording (snapshots/live thumbnails). Nothing else.
- Code signing: rebuilt ad-hoc-signed apps lose their permissions on every build (we hit this). The project needs a stable signing identity from the start. Owner has no signing certificate yet; free Apple ID in Xcode is the recommended route for development. Public releases will eventually need a paid Apple Developer ID for notarization (owner's later decision).
- Open source, hosted on GitHub. License choice is deferred.

## How it works (decided parts)

- **Hiding a parked window:** move it via Accessibility so it sits almost entirely off-screen at a corner (technique used by AeroSpace). Not minimize (wrong animation), not app-hide (hides all of an app's windows).
- **Transitions:** a transparent, click-through overlay window draws window snapshots. Real windows swap with snapshots only once the snapshot is on screen (stage → strip) or after the snapshot lands and the real window has drawn (strip → stage).
- **Strip interaction:** a separate non-activating panel receives clicks/hover so clicking the strip never steals focus from the user's app.
- **Matching Apple's feel:** Apple's tuning values (strip corner radius, pile rotation, perspective distance, spacing, animation speed, auto-hide delay, hover scale distance, etc.) exist as named preferences in `WindowManager.framework`; their numbers are compiled into code. Get the real numbers either by decompiling with Ghidra (needs Ghidra + Java installed; ask owner first) or by frame-by-frame measurement of screen recordings of Apple's Stage Manager. Builder picks; both are fine.

## Design decisions to check

- **How stages form: match Apple.** Each app starts as its own stage. Combine by dragging a strip item onto the stage or shift-clicking it; pull a window out by dragging it to the strip. Cmd-Tab to an app whose windows are in several stages brings forward the stage holding its most recently used window. (Follows from "close to Apple Stage Manager".)
- **Turning off Apple's Stage Manager:** on first launch, if Apple's is on, Podium explains and offers a button that turns it off (with the user's click). Podium does not turn Apple's back on automatically on quit; the menu offers it.
- **Notarization:** not needed for v1 development builds. Decide before the first public release; it doesn't block building.

## Team review outcomes (PM, Architect, Developer, QA — 2026-10-21)

Owner feedback on the upgraded spike: minimize still goes to the Dock, and other windows aren't hidden the way Stage Manager hides them. Root cause of both: those features were never in the spike (it parks one chosen window and has no stage model or minimize handling). They are core v1 work, not spike patches.

**Blocking (raised by all four): window safety comes before any polish.**
- Hiding every off-stage window means Podium moves almost every window on the system. A crash must never strand them.
- Before each move, write the window's original frame to a persisted record. On launch, restore anything left parked. Menu has "Restore all windows". Quit restores all.
- Cover: crash/kill -9 mid-animation, sleep/wake, display plug/unplug or resolution change, apps quitting while parked, windows that refuse or clamp moves, sheets/dialogs, full-screen windows, Accessibility permission being revoked.
- An automated "kill mid-park, relaunch, assert every window is back on-screen" test exists before feature work.

**Minimize-to-strip: intercept first, with a safe fallback.**
- Primary: event tap catches the minimize button click / Cmd-M (Accessibility hit-test) and parks instead.
- Fallback for misses (Window menu, custom title bars like Chrome/Electron, remapped keys): watch for the window becoming minimized, un-minimize it, park it. The Dock's genie may flash in that case; acceptable only as a fallback.
- If macOS disables the event tap (slow taps get killed), re-enable it; minimize must never be swallowed without being handled.

**Private APIs.** The Architect noted that SIP-free private calls can list and order windows (what AltTab uses) but can't move, scale or fade other apps' windows. That needs SIP off. So they won't make the animation smoother; the snapshot overlay is the smoothness mechanism either way. Allowed: small SIP-free helpers with a public-API fallback.

**Signing is day one.** Rebuilds lose permissions without a stable signing identity; fix before the first v1 build.

**Measurable "feels like Apple" (acceptance).** Record Apple's Stage Manager and Podium doing the same scenarios (switch stage, minimize, combine, hover, auto-hide). Pass when: no visible blink at the swap, timing within ~10% of Apple's, click-to-motion latency under ~50 ms, no dropped frames at 120 Hz, and the owner can't reliably tell them apart side by side.

**Recommendations pending owner OK:**
- Tuning values come from frame-by-frame screen recordings, not Ghidra (three of four roles: faster, measures what users see, avoids legal questions for an open-source project).
- v1 runs on the main display only, but the stage model is display-aware from the start so multi-display doesn't need a rewrite. Plugging in or removing a display while windows are parked restores them safely.

## Findings from Stage Manager internals (see `docs/research/2026-10-21-stage-manager-internals.md`)

- Motion must use **interruptible, velocity-preserving springs** (Apple's `SpringBehavior`/`_C2SpringIntegration`). Podium runs its own per-frame spring engine rather than restarting Core Animation springs. This is the most likely gap behind "smooth but not Apple smooth".
- Structure Podium like Apple's: one model of stages and windows → pure layout functions (strip side is just an input) → transitions that animate between layouts.
- Apple moves real windows with private window-server transforms; Podium can't, so snapshot/live-capture handoff stays. Batch window moves so all changes land in the same frame.
- Hover and click-down scale by a distance in points, with latching; auto-hide uses an overlap threshold, a delay and a thin peek width.

## Left to the builder

- Code structure, module boundaries, testing approach.
- How live thumbnails are produced (per-window streams vs periodic captures) within a sensible CPU/battery budget.
- Exact auto-hide and hover thresholds, once Apple's numbers are known.
- How stranded-window recovery is stored.
- Settings window layout.

## Risks to check early

- Can ScreenCaptureKit keep capturing a window that has been moved almost off-screen? Live thumbnails depend on it.
- Apps that refuse or fight Accessibility moves (some Electron/Java apps, windows with minimum sizes, full-screen windows).
- Multiple displays and the menu bar/notch area when computing positions.
- Snapshot latency on click; may need cached snapshots refreshed in the background so motion starts instantly.
