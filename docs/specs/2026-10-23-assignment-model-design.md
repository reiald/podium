# Podium core: Apple's stage assignment model

Source of the rules: `docs/research/2026-10-23-apple-stage-assignment.md` (R1–R18 below are its "Rules for Podium").

## Why

`StageBoard` edits stages imperatively: each event moves windows between stages. Small focus or drag
events then leave the board half-swapped or split. Apple keeps a few inputs and recomputes the whole
layout from them on every change. Podium does the same.

## Model

`StageBoard` keeps its public API (events in, `stages` / `activeStage` / `stripStages` out), so
`Coordinator`, `TransitionPlan`, the runner and the presenter keep working. Its internals change:

Stored inputs only:
- `zOrder: [WindowRef]`: every board window, most recently focused first (Apple's window z-order).
- `userSets: [UserSetID: [WindowRef]]`: windows the user combined (drag onto stage, shift-click).
- `minimized: Set<WindowRef>`, `hidden: Set<Int32>`, `grouping`.
- `proposal: WindowRef?`: the window that should be in front (Apple's `currentWindowProposal`).
- `emptyStage: Bool`: show the desktop (`stageStyle = .empty`) until the next proposal.
- `stripSlots: [GroupID]` and `previousStageGroup: GroupID?`: Apple's `ComponentState`.
- `replacementOrder` (`.stableLeastRecentlyUsed` default, `.recency`) and `maximumRowCount`.

Derived on every change by one pure function, `assign(...)`:
1. Groups (R1–R4, R6): walk `zOrder`; a window in a user set spanning several apps → group
   `.crossAppSet(id)`; else group `.process(pid)`. Groups ordered by first visit (front window
   first). Hidden apps' windows are skipped.
2. Window sets per group (R2, R3, R5): single-app user set → one set; loose windows → one set each,
   merged into one `.process` set in All at Once at the first loose window's position; each
   minimized window → its own `.minimized` set (before the rest if the front window is minimized).
3. Stage group (R7, R8): the first group containing `proposal`; else the first group with a
   non-minimized set; none when `emptyStage`.
4. Stage window set (R9): the stage group's first non-minimized set. Its windows are `activeStage`.
5. Strip candidates (R10): every group; the stage group is dropped only if it has exactly one set
   and that set is not minimized. A stage group that stays shows its remaining windows in the strip.
6. Strip order (R11, R12): `.recency` = candidate order; `.stableLeastRecentlyUsed` = Apple's
   slot-keeping algorithm over the first `maximumRowCount` slots, previous stage group first in line.

Output mapping to the existing types: `Stage.id` is a deterministic UUID derived from the group ID
(plus a "rest" marker for a stage group's strip item), so ids are stable across recomputes.

## Events (StageBoard API → inputs)

| Event | Inputs changed | Rule |
|---|---|---|
| `windowOpened(w)` | insert at front of zOrder, `proposal = w` | R17 off by default |
| `windowFocused(w)`, `show(w)`, `deminimize(w)` | move to front, unminimize, `proposal = w`, `emptyStage = false` | R7 |
| `appActivated(pid)` | proposal = app's most recent non-minimized window | R7 (Inferred in spec) |
| `select(item)` | if the item has no non-minimized window, unminimize its front one; proposal = item's front non-minimized window | R7, R9 |
| `windowClosed(w)`, `minimize(w)`, `moveToPile(w)` / drag-out | remove (or mark minimized); remove from its user set; if `w` was the proposal, propose another stage window, same app first, else `emptyStage` | R15, R18 |
| `addToActiveStage(w)`, `combineIntoActive(item)` | add the window(s) to the stage's user set, creating it from the stage set's windows if none; unminimize; proposal = w | R14 |
| `showDesktop()` | `emptyStage = true` | R8 |
| `appHidden/Unhidden`, `appTerminated`, `setGrouping` | as named | |

Drag-out of a loose All at Once window behaves as minimize to strip: the window stays in its app's
group as a minimized set, shown in the strip under the app (Apple's minimized-window treatment).

## Tests

One test (at least) per rule R1–R16, written first and failing. Existing `StageBoardTests` that encode
the old imperative behaviour are updated to Apple's behaviour or deleted, never left asserting the old
one. `TransitionPlan` tests stay green.
