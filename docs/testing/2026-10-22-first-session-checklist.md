# Podium: first real-window test session

This is your checklist for the first time Podium runs against real windows. Nothing in it has been seen on a real screen yet, so some things may look wrong. That is what this session is for. Take your time, and write down anything odd, even if it is not on the list.

For each item: do the step, compare with "You should see", then tick Pass or Fail and jot a note.

## 1. Before you start

1. **Make the signing certificate (once).** In Terminal: `cd ~/Documents/podium && scripts/make-dev-cert.sh`. It may ask for your keychain password. This keeps your permissions from resetting after every rebuild.
2. **Build and launch:** `scripts/run.sh`. It rebuilds and opens `build/Podium.app`.
3. **Grant Accessibility.** System Settings > Privacy & Security > Accessibility > switch on **Podium** (use the + button if it is missing, and pick `build/Podium.app`).
4. **Grant Screen Recording.** System Settings > Privacy & Security > Screen & System Audio Recording > switch on **Podium**. macOS usually wants you to quit and reopen the app after this. Podium's setup window has a "Quit & Reopen Podium" button for it.
5. **Keep Apple's Stage Manager OFF.** System Settings > Desktop & Dock > Stage Manager > off. Podium also won't run while it is on.
6. **Keep it simple for the first pass:** one display, one Space, no full-screen apps.
7. **Emergency button:** the Podium menu-bar item > **Restore All Windows**. Use it any time something looks stuck.
8. **If Podium crashes,** just reopen it. On launch it puts every window back.
9. **Open Activity Monitor** (Applications > Utilities) and search "Podium" to watch memory and CPU.
10. Handy: leave `log stream --predicate 'subsystem == "dev.podium.Podium"'` running in a second Terminal window.
11. Open a few apps with one window each (Safari, Notes, TextEdit) plus a Finder window.

## 2. Safety first

**1. The kill test**
- Do: quit Podium, close any open TextEdit documents (the script refuses to run if any are open), then run `cd ~/Documents/podium && pkill -x Podium; scripts/kill-test.sh`
- You should see: `10/10 passed`, and a line saying a non-zero number of kills happened after parking (for example `7/10 kills happened after parking`). Zero is a failure.
- [ ] Pass  [ ] Fail
- Notes:

**2. Kill during a strip click**
- Do: with 3 apps open and Podium running, click a strip thumbnail and, while it animates, run `kill -9 $(pgrep -x Podium)` in Terminal. Then reopen Podium (`open build/Podium.app`).
- You should see: after relaunch, every window is back on screen. Nothing is stuck in the bottom-right corner.
- [ ] Pass  [ ] Fail
- Notes:

**3. Quit, terminate and Restore All**
- Do: with windows parked, try each of: Podium menu > Quit; `pkill -INT Podium` (after reopening); and Restore All Windows.
- You should see: every window returns to its original spot each time. After Restore All, the menu says "Turn Podium On" (it stays off until you turn it on).
- [ ] Pass  [ ] Fail
- Notes:

## 3. Stages and hiding

**4. Launch**
- Do: with Safari, Notes and TextEdit open, start Podium.
- You should see: only the front app stays on screen. The others shrink into tilted thumbnails on the right edge, each with its app icon in the corner. No empty slots (blank slots mean Screen Recording is missing).
- [ ] Pass  [ ] Fail
- Notes:

**5. Switching with Cmd-Tab**
- Do: Cmd-Tab to Notes, then to Safari, then back to Notes.
- You should see: only the frontmost app's windows are on screen and the screen is never empty. Windows return to exactly the spot they left.
- [ ] Pass  [ ] Fail
- Notes:

**6. New window joins its stage**
- Do: in Notes press Cmd-N.
- You should see: both Notes windows stay on screen together.
- [ ] Pass  [ ] Fail
- Notes:

**7. Piles**
- Do: give an app 4 windows, then switch away. Then try 5 windows and switch away.
- You should see: a thumbnail shows at most 3 stacked cards, the front one with the app icon. Switching back brings all windows back (the extras may fade in).
- [ ] Pass  [ ] Fail
- Notes:

**8. Shift-click a thumbnail**
- Do: Shift-click a thumbnail.
- You should see: that stage's front window flies in and joins the current stage. The current windows stay.
- [ ] Pass  [ ] Fail
- Notes:

**9. Drag a thumbnail onto the stage**
- Do: press on a thumbnail, drag it out of the strip and let go.
- You should see: all of that stage's windows join the current stage.
- [ ] Pass  [ ] Fail
- Notes:

**10. Drag a window into the strip**
- Do: in a stage with 2+ windows, drag one window by its title bar and release with the pointer over the strip. Then click the new thumbnail.
- You should see: that window flies into the strip as its own stage and the rest stay. Clicking the thumbnail returns it to where it was before the drag, not over the strip. A window alone in its stage does nothing when dragged there, and neither does resizing a window into the strip.
- [ ] Pass  [ ] Fail
- Notes:

**11. Focus a parked window another way**
- Do: use Cmd-` , the app's Window menu, the Dock's right-click window list, or Mission Control to pick a window that is parked.
- You should see: that window's stage comes forward and the previous stage is parked.
- [ ] Pass  [ ] Fail
- Notes:

**12. Quit an app whose windows are parked**
- Do: quit Notes while its stage is in the strip.
- You should see: its thumbnail disappears. Restore All or Quit afterwards still returns all other windows.
- [ ] Pass  [ ] Fail
- Notes:

**13. Window of a quit app returns**
- Do: quit an app while one of its windows is parked, relaunch it, and focus its window (Cmd-` or Window menu).
- You should see: the window comes back on screen, not stuck as a 1-point speck in the corner.
- [ ] Pass  [ ] Fail
- Notes:

## 4. Strip: both sides, hover, auto-hide

**14. Hover**
- Do: move over a thumbnail, across the gap to the next, then off the strip.
- You should see: the hovered cards grow about 8 pt with a quick spring. Crossing the gap does not flicker. Leaving shrinks them back.
- [ ] Pass  [ ] Fail
- Notes:

**15. Auto-hide**
- Do: drag a window so it covers more than 15% of the strip and move the pointer off the strip. Then push the pointer to the very right edge.
- You should see: after about a quarter second the strip (shadows too) slides off the right edge. Clicks there now reach the window. Pushing to the edge slides the strip back.
- [ ] Pass  [ ] Fail
- Notes:

**16. Clicks under the strip pass through**
- Do: with the strip showing, click and drag a window's scroll bar (and click content) inside the strip's area but not on a thumbnail.
- You should see: the click reaches the window as normal. Thumbnails still hover, click and drag.
- [ ] Pass  [ ] Fail
- Notes:

**17. Flip side**
- Do: Podium menu > Strip on Left (then back to Right). Repeat a few of the checks above (switching, hover, auto-hide, drag) on the left.
- You should see: all cards fly across live, tilt mirrored, icon on the corner facing the stage. Everything works on both sides.
- [ ] Pass  [ ] Fail
- Notes:

**18. Card look**
- Do: study a thumbnail up close.
- You should see: title bar at the top, content not upside down or mirrored, tilt that looks like Stage Manager's, smooth rounded corners and a soft shadow.
- [ ] Pass  [ ] Fail
- Notes:

## 5. Animations (no blink)

**19. Leaving the stage**
- Do: click a thumbnail and watch the old windows.
- You should see: they shrink smoothly into the strip. No flash, no frame of empty desktop where the window was.
- [ ] Pass  [ ] Fail
- Notes:

**20. Entering the stage**
- Do: watch the clicked thumbnail grow.
- You should see: it grows to the window's exact spot and the real window takes over invisibly. No one-frame gap, no double image, no jump.
- [ ] Pass  [ ] Fail
- Notes:

**21. Fast clicking**
- Do: click two thumbnails alternately as fast as you can, including thumbnail-to-thumbnail clicks while a transition is still running.
- You should see: cards bend and turn around smoothly. No click ever falls through to the desktop (no Finder or desktop icon reacting). When you stop, the right stage is on screen and every other window is parked.
- [ ] Pass  [ ] Fail
- Notes:

**22. Dropped frames**
- Do: after a few transitions, check the log window for "dropped frame".
- You should see: few or none. Also no park or unpark failures in the log.
- [ ] Pass  [ ] Fail
- Notes:

## 6. Minimize to strip

Keep the log open and watch lines starting with "minimize tap" or "un-minimize".

**23. Yellow button, stage with 2+ windows**
- Do: Shift-click to combine stages, then click one window's yellow button (TextEdit, Safari, Notes).
- You should see: no genie. The window shrinks into the strip as its own front thumbnail, the other windows stay, and nothing goes to the Dock.
- [ ] Pass  [ ] Fail
- Notes:

**24. Yellow button, lone window**
- Do: minimize a window that is alone in its stage, then click its thumbnail.
- You should see: it flies to the strip and the stage area is empty. Clicking the thumbnail brings it back to its old frame.
- [ ] Pass  [ ] Fail
- Notes:

**25. Cmd-M**
- Do: press Cmd-M (try holding it).
- You should see: same as the yellow button, and exactly one window moves per press (no cascade).
- [ ] Pass  [ ] Fail
- Notes:

**26. Option-click and Option-Cmd-M**
- Do: Option-click the yellow button, and try Option-Cmd-M.
- You should see: normal macOS behavior, all of that app's windows genie into the Dock and stay out of the strip. Window > Minimize more than 2 seconds later goes to the strip.
- [ ] Pass  [ ] Fail
- Notes:

**27. Window > Minimize menu**
- Do: use Window > Minimize in TextEdit.
- You should see: a brief genie, the window comes back, then flies into the strip. No "still minimized" line in the log.
- [ ] Pass  [ ] Fail
- Notes:

**28. Normal clicks are never swallowed**
- Do: click title bars, close and zoom buttons, select text, type plain M and Shift-Cmd-M, click a menu-bar app's window.
- You should see: everything works as usual and no click gets stuck half-pressed. A greyed-out minimize button does nothing.
- [ ] Pass  [ ] Fail
- Notes:

**29. Minimize to Dock setting**
- Do: Podium menu > Minimize to Dock, then try yellow button, Cmd-M and Window > Minimize. Switch back afterwards.
- You should see: all three genie into the Dock as in stock macOS.
- [ ] Pass  [ ] Fail
- Notes:

**30. Dock-minimized windows and Cmd-Tab**
- Do: open two Notes windows A and B (A last). Minimize A to the Dock (Dock setting, or Option-click). Cmd-Tab to Safari, then back to Notes. Then un-minimize A from the Dock.
- You should see: B's stage comes forward and B is on screen (never an empty screen). Un-minimizing A brings A's stage forward. A Dock-minimized window has no strip slot.
- [ ] Pass  [ ] Fail
- Notes:

**31. Focus after a lone minimize**
- Do: minimize the only window of a stage to the strip, then type.
- You should see: keys do not go to the parked window. Finder (the desktop) is active.
- [ ] Pass  [ ] Fail
- Notes: (If focus stays on a parked window, write that down. macOS may be refusing to switch focus.)

**32. Same check with a Finder window in the strip**
- Do: park a Finder window in the strip, minimize a lone window to the strip, then type.
- You should see: keys go nowhere harmful (Podium makes itself active instead of Finder). Minimizing a lone Finder window itself also hands focus to Podium, not the desktop. That is a known limit.
- [ ] Pass  [ ] Fail
- Notes: (Again note it if focus stays on a parked window.)

**33. Focus after drag-out**
- Do: drag a window of a two-window stage into the strip, then type.
- You should see: the remaining window has focus.
- [ ] Pass  [ ] Fail
- Notes:

**34. Chrome and an Electron app**
- Do: run checks 23, 25 and 27 in Chrome and in VS Code or Slack.
- You should see: write down per app whether it went to the strip, fell back to the Dock, or something else. Note if their custom title-bar buttons are ignored.
- [ ] Pass  [ ] Fail
- Notes:

**35. Other keyboard layout (optional)**
- Do: add the French AZERTY input source and switch to it. In TextEdit try Cmd-, (physical M key position on a US keyboard) and Cmd-M.
- You should see: Cmd-, opens Settings and sends nothing to the strip. Cmd-M (whichever key types "m") sends the window to the strip.
- [ ] Pass  [ ] Fail
- Notes:

**36. Quit restores stock minimize**
- Do: after quitting Podium, click a yellow button.
- You should see: normal macOS genie in every app.
- [ ] Pass  [ ] Fail
- Notes:

## 7. Settings and onboarding

**37. First-run setup**
- Do: Terminal: `defaults delete dev.podium.Podium`, then reopen the app.
- You should see: a setup window. Grant buttons open the right System Settings panes and checkmarks flip within about a second. Done is only clickable when both permissions are on and Apple's Stage Manager is off. After Done, the strip starts. After granting Screen Recording, if it still shows unticked, "Quit & Reopen Podium" fixes it.
- [ ] Pass  [ ] Fail
- Notes:

**38. Turn Podium Off and On**
- Do: menu > Turn Podium Off, then On. Repeat several times.
- You should see: Off restores every window and removes the strip. On brings it back each time.
- [ ] Pass  [ ] Fail
- Notes:

**39. Menu toggles**
- Do: flip Minimize to Strip/Dock and Auto-hide Strip.
- You should see: they take effect immediately. With auto-hide off the strip never slides away.
- [ ] Pass  [ ] Fail
- Notes:

**40. Apple's Stage Manager row**
- Do: with Apple's Stage Manager on, click "Open Stage Manager settings", turn it off, and come back.
- You should see: the row disappears within about a second. The menu shows "Turn Apple's Stage Manager Back On", which takes you to the settings to re-enable it.
- [ ] Pass  [ ] Fail
- Notes:

**41. Apple's Stage Manager turned on while running**
- Do: turn Apple's Stage Manager on while Podium is running, then off again.
- You should see: every window is restored and the setup window explains. Podium manages nothing until you turn it off, then it resumes by itself.
- [ ] Pass  [ ] Fail
- Notes:

**42. Revoke and regrant Accessibility**
- Do: with windows parked, remove Podium from Accessibility, then add it back. Also try Restore All with Accessibility removed, then regrant.
- You should see: an alert appears, the strip disappears and parked windows stay parked. After regrant, windows are restored and Podium restarts on its own. Removing Screen Recording also stops Podium until it returns.
- [ ] Pass  [ ] Fail
- Notes:

## 8. Capture and live thumbnails

**43. Do parked windows keep streaming? (the T10 check)**
- Do: run these in Terminal. TextEdit must have one document open first.
  ```
  open -a TextEdit && osascript -e 'tell application "TextEdit" to make new document'
  scripts/run.sh   # then quit Podium: pkill -x Podium
  open build/Podium.app --args --debug-capture-parked com.apple.TextEdit
  for i in $(seq 1 20); do osascript -e 'tell application "TextEdit" to set text of front document to (text of front document) & "podium "'; sleep 1; done
  log show --last 2m --style compact --predicate 'process == "Podium"' | grep 'debug capture'
  ```
- You should see: YES means `frame N ... dt~1.0 ... content=changed` lines keep coming while the loop types, and the summary shows `changes` near the number of edits. NO means only a `first` frame (or none) and `changes=0`. Both answers are useful.
- [ ] Pass (YES)  [ ] Fail (NO)
- Notes:

**44. Snapshot and unpark in the same run**
- Do: look at the same log output.
- You should see: `on-stage snapshot ... ok`, steady frame times, `unpark ok`, and the TextEdit window back where it was.
- [ ] Pass  [ ] Fail
- Notes:

**45. Live thumbnails in normal use**
- Do: park a TextEdit stage, then type in it from another window (or edit via the script above) and watch its thumbnail.
- You should see: it updates live, about 5 times a second. The strip shows nothing streaming while it is hidden.
- [ ] Pass  [ ] Fail
- Notes:

**46. Memory with many windows**
- Do: open 20+ windows across stages and watch Podium in Activity Monitor.
- You should see: memory stays well under a few hundred MB.
- [ ] Pass  [ ] Fail
- Notes: (peak MB)

**47. Screen-recording indicator and CPU with 15+ cards**
- Do: get 15+ cards in the strip and watch the purple/orange screen-recording indicator in the menu bar and Podium's CPU for a minute.
- You should see: the indicator is not stuck flashing in a way that bothers you, and CPU stays modest when you are idle. Note the CPU numbers.
- [ ] Pass  [ ] Fail
- Notes: (CPU %)

## 9. Edge cases

**48. Spaces recovery**
- Do: on Space 2 park some windows, `kill -9 $(pgrep -x Podium)` while on Space 1, relaunch on Space 1, then switch to Space 2.
- You should see: those windows come back (log: "Space changed; retrying recovery").
- [ ] Pass  [ ] Fail
- Notes:

**49. Closing a Settings window**
- Do: open System Settings (or an app's Settings window) and close it.
- You should see: no ghost stage or empty strip slot left behind.
- [ ] Pass  [ ] Fail
- Notes:

**50. Hung app**
- Do: put TextEdit's stage in the strip, run `kill -STOP $(pgrep -x TextEdit)`, click its thumbnail, click its yellow button, and keep typing in Notes or Safari. Then `kill -CONT $(pgrep -x TextEdit)`.
- You should see: other apps never lag, and the log may show "minimize tap disabled... re-enabling" then "healthy again". Podium does not freeze. After CONT, TextEdit's stage recovers.
- [ ] Pass  [ ] Fail
- Notes:

**51. Display change**
- Do: System Settings > Displays, change the resolution, then change it back.
- You should see: parked windows stay parked and the visible stage is unaffected.
- [ ] Pass  [ ] Fail
- Notes:

**52. Full-screen app (later pass, optional)**
- Do: put an app in full screen.
- You should see: neither the strip nor cards draw over it, and clicks at the edge reach the app.
- [ ] Pass  [ ] Fail
- Notes:

## 10. What to send back

1. The list of item numbers that failed, with your notes for each (anything odd on a passing item too).
2. For the capture check (item 43), paste the output of the last command:
   `log show --last 2m --style compact --predicate 'process == "Podium"' | grep 'debug capture'`
   plus the YES or NO you decided on.
3. The kill test's final lines (`10/10 passed` and the "kills happened after parking" line).
4. Peak memory (item 46) and CPU (item 47).
5. For anything that failed, if you can: the log from `log show --last 5m --predicate 'subsystem == "dev.podium.Podium"'`.
