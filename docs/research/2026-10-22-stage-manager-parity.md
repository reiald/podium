# Podium vs Apple Stage Manager: feature parity (2026-10-22)

How to read: ✅ Podium has it · 🟡 partial · ❌ missing · ➕ Podium only.
Sources: Apple's Stage Manager on macOS 27.2 (its `com.apple.WindowManager` prefs and
behavior, see `2026-10-21-stage-manager-internals.md`) and Podium at `fa5c115`.

## Strip
| Feature | Apple | Podium |
|---|---|---|
| Strip of recent stages with live thumbnails | yes | ✅ |
| Strip side | left only | ➕ left or right |
| Thumbnail size, tilt, icon size | fixed | ➕ adjustable |
| Piles of up to 3 windows per app | yes | ✅ |
| App icon on each item | yes | ✅ detached as of `ed91a5e` |
| Click the app icon to see that app's windows | yes | ✅ `ed91a5e` |
| Auto-hide when a window covers the strip, reveal at the edge | yes | ✅ |
| "Show recent apps" off: no strip at all, edge reveal only | yes | ❌ |
| Hover lift and press feedback | yes | ✅ |

## Moving windows between stages
| Feature | Apple | Podium |
|---|---|---|
| Click a thumbnail to switch stages | yes | ✅ |
| Shift-click to add to the stage | yes | ✅ |
| Drag a thumbnail onto the stage to add it | yes | ✅ `5bc7147` |
| Drag a window by its title bar into the strip | yes | ✅ |
| Drag a file onto a thumbnail: the stage opens so you can drop into its window | yes | ❌ |
| All at Once / One at a Time | yes | ✅ |

## Window lifecycle
| Feature | Apple | Podium |
|---|---|---|
| Minimize goes to the strip | yes | ✅ (➕ can choose the Dock) |
| Click the Dock icon to minimize / restore | no | ➕ |
| New window of an on-stage app joins the stage | yes | ✅ |
| Closing a window doesn't pull a strip window on stage | yes | ✅ `fa5c115` |
| Cmd-Tab, Dock and Mission Control bring the stage forward | yes | ✅ |
| Cmd-H hides an app: its stage leaves the strip until unhidden | yes | ❌ not handled |
| Full-screen and Split View apps leave the stage cleanly | yes | ❌ not handled |

## Desktop
| Feature | Apple | Podium |
|---|---|---|
| Click the wallpaper to send everything to the strip and show the desktop | yes | ❌ |
| Hide desktop items while using it (toggle) | yes | ❌ |
| Hide widgets while using it (toggle) | yes | ❌ |

## System integration
| Feature | Apple | Podium |
|---|---|---|
| Separate strip and stages on each display | yes | ❌ main display only |
| Separate stages per Space | yes | 🟡 recovers windows on a Space switch, no stages per Space |
| On/off from Control Center | yes | 🟡 menu bar only |
| Keyboard shortcut to turn it on/off | via Shortcuts | ❌ |
| Starts at login | built in | ❌ no login item |
| Reduce Motion (crossfades instead of flights) | yes | ❌ |
| VoiceOver can read and pick strip items | yes | ❌ |

## Ease of use found while testing
- Podium refuses to run while Apple's Stage Manager is on. It is on right now
  (`GloballyEnabled = 1`), so Podium is idle until you turn it off.
- "Restore All Windows" leaves Podium off afterwards, which reads as broken.
- The app view's known rough edges (`appview-report.md`): Esc during a drag also closes the
  view; a window leaving the stage while the view is open fades in place.

## Roadmap
1. **Daily use.** Cmd-H and full-screen handling; click the wallpaper to show the desktop;
   start at login; a global on/off shortcut. These cause the "unfinished" feeling most.
2. **Multiple displays.** One strip and board per display. The biggest piece of work: the
   Coordinator, runner and presenter assume one display today.
3. **Desktop and drag-and-drop.** Hide desktop items and widgets toggles; drop a file onto a
   thumbnail; "Show recent apps" off.
4. **Accessibility.** Reduce Motion; VoiceOver labels and actions for strip items.
5. **Spaces.** Stages per Space.
