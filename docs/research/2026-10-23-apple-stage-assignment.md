# Apple Stage Manager: how windows are assigned to the stage and the strip

Date: 2026-10-23
Target: `WindowManager` (Stage Manager's process), arm64e slice, stripped Swift.
Tools: Ghidra 12.1.4 through REA, `ipsw swift-dump` for type names, enum cases and witness tables.

Tags used below:
- **Observed**: read directly from a decompiled branch, a field offset or a call site.
- **Inferred**: the most likely reading where the decompilation is ambiguous (register aliasing, Swift enum encoding, stripped helpers). Each one says why.

Function addresses are virtual addresses in this binary. Swift enum tags are numbered in declaration order. For multi-payload enums the tag byte sits after the payload; for `StageManagerContainerGroup.ID` the case lives in the top 2 bits of that byte (`0x00` crossAppSet, `0x40` process, `0x80|sub` processWindowSet).

## 0. Pipeline overview

Stage Manager is built from small value "components". Each space runs this pipeline (fields from `StageManagerSpaceComponent`):

```
windows ──► StageManagerWindowDestinationComponent   (WindowID → WindowDestination)
        ──► StageManagerWindowGroupComponent          (builds containerGroups, ordered)
        ──► StageManagerStageStripAssignmentComponent (stage group, strip order, hidden groups)
        ──► StageManagerStripComponent / FreeformComponent (layout)
user actions ──► StageManagerComputeTransientWindowSetOperationsComponent
              ──► [StageManagerTransientWindowSetOperation]
              ──► StageManagerApplyTransientWindowSetOperationsComponent / StageManagerWindowSetModelComponent
              ──► StageManagerUserWindowSetRegistry (persisted user window sets)
```

There are two assignment components: `stageStripAssignmentComponent` and `exposeStripAssignmentComponent`. The second is the one that uses `exclusiveProcessSerialNumbers` (see 3.4).

Witness tables found through `ipsw swift-dump -V` and `read_bytes`. In each LayoutComponent table, slots [4] and [5] are the event and update handlers; ValueComponent slot [3] is the `outputModel` getter.

| Component | outputModel / update |
|---|---|
| StageManagerWindowGroupComponent | `0x10031e6f8` → `0x10031cc50` (builder) |
| StageManagerWindowDestinationComponent | `0x100315a18` → `0x100313d0c` |
| StageManagerStageStripAssignmentComponent (class) | `0x1002e5760` (output), `0x1002e54c8`, `0x1000333c0` |
| StageManagerComputeTransientWindowSetOperationsComponent | output `0x10029827c` → `0x100297404`; event `0x1002982c0` → `0x100297380` |
| StageManagerApplyTransientWindowSetOperationsComponent | `0x10029500c` → `0x100294214` |
| StageManagerProposeKeyAndMainWindowComponent | `0x1002c58c8` → `0x1002c4100` (events), `0x1002c58cc` → `0x1002c4fc0` |
| StageManagerAutomaticAddToStageComponent | `0x1002967b4` → `0x100295dd8` |
| StageManagerMiniaturizedWindowsComponent | `0x1002ad29c` → `0x1002abc6c`, `0x1002ad2a0` → `0x1002acf64` |
| StageManagerWindowSetModelComponent | `0x10032137c` → `0x10031eedc`, `0x1003213bc` → `0x10031f9d0` |

## 1. Enum and type dumps (Observed, from swift-dump)

```
StageManagerContainerGroup { id: ID, zOrderedWindowSets: [StageManagerGroupWindowSet], representedProcessSerialNumbers (lazy) }
StageManagerContainerGroup.ID      = crossAppSet(UserWindowSet.ID) | process(PSN) | processWindowSet(PSN, GroupWindowSet.ID)
StageManagerGroupWindowSet         { id, zOrderedWindowIDs: [WindowID], representedProcessSerialNumbers }
StageManagerGroupWindowSet.ID      = userWindowSet(UserWindowSet.ID) | process(PSN) | minimizedWindow(WindowID) | window(WindowID)
StageManagerWindowDestinationComponent.WindowDestination
                                   = crossAppWindowSet(UserWindowSet.ID) | intraAppWindowSet(PSN, UserWindowSet.ID)
                                   | processPrimary(PSN) | processAppSticky(PSN) | processAccessory(PSN) | freeform
StageManagerProcessAssociatedWindowList { accessoryWindowIDs, appStickyWindowIDs }
StageStripAssignment.StageStyle    = standard | empty
StageStripAssignment.ProcessContainerWindowSetBehavior = singleWindowWithPromotion(Set<PSN>) | singleWindow | allWindows
StageManagerStripReplacementOrder  = recency | stableLeastRecentlyUsed
StageStripAssignment.StripParameters { maximumRowCount: Int, replacementOrder, exclusiveProcessSerialNumbers: Set<PSN>? }
StageStripAssignment.ComponentState / InputPreviousState { sortedStripContainerGroupIDs, stageContainerGroupID? }
StageStripAssignment.OutputModel   { containerGroups, stripContainerGroupIDs, stageContainerGroupID?, stageWindowSetID?, hiddenContainerGroupIDs }
WindowProposal                     = keyWindow(WindowID?) | mainWindow(WindowID?)
WindowProposalRequest              { id, previousKeyWindow: WindowID, proposal }
StageManagerModifyWindowSetOperation = createUserWindowSet(UserWindowSet) | addWindowToUserWindowSet(setID, WindowID)
                                     | removeWindowFromUserWindowSet(setID, WindowID)
StageManagerTransientWindowSetOperation = modify(ModifyWindowSetOperation) | orderWindowFront(WindowID)
ComputeTransientWindowSetOperations.Event = addToStage(WindowID) | removeFromStage(WindowID) | replaceWindowWithWindow(WindowID, WindowID)
ComputeTransientWindowSetOperations.InputModel { proposedStageUserWindowSetID?, stageContainerGroup?, stageWindowSetID?, userWindowSetRegistry }
StageManagerAutomaticAddToStageComponent.Action = addToStage(WindowID)
  InputModel { preferences, previousSpaceOrderedWindowIDs, previousAssignmentOutputModel,
               previousBundleIDToTerminatedPersistentWindowID, assignmentOutputModel, windowIDToWindow }
StageManagerMiniaturizedWindowsComponent.Action = orderFrontFromMiniaturize(Set) | orderFrontFromDeminiaturize(Set)
                                                | removeFromUserWindowSet(Set<WindowID>) | common
StageManagerProposeKeyAndMainWindowComponent.Action = emptyStage(PSN?, forProcess) | common
  InputModel { windows, stageWindowIDs: Set<WindowID> }
StageManagerStripStageWindowDragModifierComponent.Direction = stripToStage | stageToStrip
StageManagerUserWindowSet.ID { value: String }
```

Preferences imported from `WindowManager.framework` (Observed, `nm -u`):
- `AppWindowGroupingBehavior` = `singleWindow | singleWindowWithPromotion | allWindows`. This is the System Settings "Show windows from an application: All at Once / One at a Time" setting.
- `WindowGroupReplacementOrder` = `leastRecentUsed | top`.
- `StageManagerMinimizationBehavior` (case `.dock` is referenced).
- `enableAutomaticNewWindowAddToWindowSet`, `orderAllWindowsLimitFrontSpace`.

### 1.1 Preference → InputModel mapping (Observed, `0x1002d9928`, assembly at `0x1002db020…0x1002db1ac`)

```
appWindowGroupingBehavior == GOT[0x1005ce9a0]  → behavior word = 0            (singleWindow, Inferred: remaining case)
                          == GOT[0x1005ce9b0]  → behavior word = 1            (allWindows — symbol resolved by name)
                          == GOT[0x1005ce9a8]  → behavior word = Set<PSN> ptr (singleWindowWithPromotion)
windowGroupReplacementOrder == leastRecentUsed (GOT 0x1005cea60) → replacementOrder = 1 (stableLeastRecentlyUsed)
                           == top            (GOT 0x1005cea68) → replacementOrder = 0 (recency)
```

So **All at Once = `.allWindows`, One at a Time = `.singleWindow`** (Observed for allWindows; singleWindow by elimination). The strip's "replace the clicked slot" behaviour is `leastRecentUsed → .stableLeastRecentlyUsed`. Which value macOS ships as the default was not checked.

## 2. Q1: how container groups are formed

### 2.1 Destination per window (`StageManagerWindowDestinationComponent`, `0x100313d0c`)

Every window gets one `WindowDestination`. The classifier (1500 decompiled lines) looks at window type, level, collection behaviours, `AppInfo.behaviorQuirks` bit 2, and user window set membership. I did not fully trace it, so only the outline is given here.
- A window in a user window set whose found properties span more than one process gets `crossAppWindowSet(id)`. A window in a user set whose windows all belong to one process gets `intraAppWindowSet(psn, id)`. **Inferred** from the case names and from `UserWindowSetFoundProperties { windowIDs, processSerialNumbers }`; the exact branch was not isolated.
- Normal app windows get `processPrimary(psn)`. Sticky windows and accessory windows (panels and similar) get `processAppSticky` and `processAccessory`. Windows that must stay free get `freeform`. **Inferred** from the names; the classifier branches exist but I did not map them.

### 2.2 Group building (`StageManagerWindowGroupComponent`, builder `0x10031cc50`, per-process helper `0x10031dfc4`) — Observed

The builder walks the input windows in order and switches on the destination tag (`switch((char)puVar22[3])` at decompiled line 295):

| tag | destination | effect |
|---|---|---|
| 0 | crossAppWindowSet(id) | Creates the container group `.crossAppSet(id)` with one window set `.userWindowSet(id)`. That set holds every window of the user set (from `userWindowSetIDToFoundProperties`) and their PSNs. Created once, when the set's first window is reached. |
| 1 | intraAppWindowSet(psn,id) | Goes into the `.process(psn)` group (built by `0x10031dfc4`). |
| 2 | processPrimary(psn) | Goes into the `.process(psn)` group (built by `0x10031dfc4`). |
| 3 | processAppSticky(psn) | Not a group. Added to `processSerialNumberToAssociatedWindowList[psn].appStickyWindowIDs`. |
| 4 | processAccessory(psn) | Not a group. Added to `accessoryWindowIDs`. If no group exists yet, it records `psn` so that this app's group is inserted first when it is reached (`local_308` / `FUN_10015f5a8` insert-at-index). This is how a frontmost panel puts its app first. The mechanism is Observed; the purpose is Inferred. |
| 5 | freeform | Appended to `freeformWindowIDs`. |

`0x10031dfc4(psn)` builds `.process(psn)` (tag byte `0x40`). It iterates `processSerialNumberToZOrderedWindowIDs[psn]` in z-order and skips windows already consumed:
- `intraAppWindowSet(psn, id)` adds one window set `.userWindowSet(id)` holding all of that set's windows (tag 0, decompiled lines ~120-150).
- `processPrimary(psn)` adds **one window set per window**: `.window(wid)` with `[wid]`, tag 3 (lines ~152-196).

So the group component **never produces `.processWindowSet`, and never merges an app's windows into a single `.process` window set**. Each app window is its own `.window` set inside the app's `.process` group. Single-app user sets appear as a `.userWindowSet` set inside that app's group.

Group order: groups are appended in the order their first window is visited. The insert-at-index path only applies to the accessory case. The input `windows` is an `OrderedDictionary`; that it is z-ordered front-first is **Inferred** (the name `processSerialNumberToZOrderedWindowIDs` and the strip behaviour fit this).

### 2.3 Reshaping inside the assignment component (`0x1002e5760` → `0x100150eb8` (OrderedDictionary.map) → closure `0x1002e69cc`) — Observed

Before choosing the stage, every group goes through `0x1002e69cc(id, group, input, miniaturizedWindowIDs)`.

**(a) "All at Once" merge**, lines 74-334:
```
if id is .process(psn) && behavior != 0 /*not .singleWindow*/ &&
   (behavior == 1 /*.allWindows*/ || behaviorSet.contains(psn) /*.singleWindowWithPromotion*/):
    concatenate the zOrderedWindowIDs of all `.window(_)` sets (tag 3) into one array
    replace them with ONE set `.process(psn)` (tag 1) at the position of the first `.window` set
    keep every other set (.userWindowSet, …) where it was
```
So in All at Once an app's group is `[.process(all loose windows)]` plus any intra-app user sets. In One at a Time it stays `[.window(w1), .window(w2), …]`. With `singleWindowWithPromotion`, the PSNs in the set get All at Once treatment. Who fills that set was not traced.

**(b) Minimized windows**, lines 335-594. For each window set, its windows are split into not-minimized and minimized (membership in `miniaturizedWindowIDs`):
- No minimized windows: the set is unchanged.
- Otherwise each minimized window becomes its own set `.minimizedWindow(wid)` (tag 2) with the same represented PSNs, in the same container group:
  - all windows minimized → only the `.minimizedWindow` sets remain;
  - the set's first (frontmost) window was minimized → `[.minimizedWindow…, remainingSet]`;
  - otherwise → `[remainingSet, .minimizedWindow…]`.

So **minimized windows stay in their app's (or cross-app set's) container group, as separate minimized window sets**. They do not get a group of their own.

### 2.4 Answer to "some of an app's windows are in a user set, some not"

- Cross-app user set: those windows form a separate `.crossAppSet` group. The app's other windows form its `.process` group. The app therefore appears in two strip piles. (Observed: separate switch cases and separate keys.)
- Single-app user set: one `.process(psn)` group holding a `.userWindowSet` set plus the loose windows (one `.window` set each, merged into one `.process` set in All at Once). (Observed.)

## 3. Q2/Q3: stage choice and strip order (`0x1002e5760`)

Input field offsets (Observed from the copy at `0x1002e5788…`, base `x29-0xd8`): +0x00 containerGroups, +0x10 miniaturizedWindowIDs, +0x18 stageStyle (byte), +0x20 maximumRowCount, +0x28 replacementOrder (byte), +0x30 exclusivePSNs?, +0x38 processContainerWindowSetBehavior, +0x40/+0x48 currentWindowProposal (tag `0xff` = nil), +0x50.. overridePreviousState.

### 3.1 Stage group — Observed
1. `0x1002e76b8`: walk the (reshaped) groups in order; inside each, walk every window set and every window. Return the **first group containing the window named by `currentWindowProposal`** (`FUN_1001199fc(windowID, proposal)`).
2. If none is found (no proposal, or its window is in no group), `0x1002e79b0` returns **the first group in order that has at least one window set that is not `.minimizedWindow`** (loop breaks on `tag != 2`).
3. If `stageStyle != .standard` (`local_d0 != 0`, i.e. `.empty`), the found group is discarded. `stageContainerGroupID = nil` and `stageWindowSetID = nil`: an empty stage, i.e. the desktop (`FUN_1002e961c` path).
4. Otherwise `stageWindowSetID` is the **first window set in the stage group's z-order that is not `.minimizedWindow`** (nil if all are minimized).

The previous stage is not consulted when picking the stage; only the proposal and group order are. **Observed.** If the proposed window moves to another group, the stage follows it at the next update. The previous stage group then feeds strip ordering (3.3).

### 3.2 Is the stage group also in the strip? — Observed (lines ~253-300 of `d1002e5760.c`)
The strip candidate list starts as all group IDs in order. The stage group's ID is removed (`FUN_1001d31dc` = firstIndex, then remove) **only if the stage group has exactly one window set and that set is not minimized**. Otherwise the stage group **stays in the strip candidates**:
- One at a Time with ≥2 windows: the app also shows in the strip with its other windows.
- The app has minimized windows: they show in the strip under the app.
- An intra-app user set plus loose windows: same, the group stays.

The strip component draws the pile for that group without the stage window set. That last detail is **Inferred**; I did not read the strip drawing code.

### 3.3 Strip order (`0x1002e7b54`) — Observed
Call site `0x1002e5d38`: `x0` = previous `sortedStripContainerGroupIDs` (from `overridePreviousState` if given, else ComponentState), `x1` = candidates, `x2..x5` = previous `stageContainerGroupID`, stack `[sp+9]` = replacementOrder, `[sp+0x10]` = maximumRowCount.

- **`.recency` (0)**: return the candidates unchanged. Strip order is then the container-group order, i.e. window z-order: most recent first (Inferred via 2.2).
- **`.stableLeastRecentlyUsed` (1)**:
  1. `working = candidates`. If the previous stage group is in `working`, move it to index 0.
  2. `prevPrefix = previousSorted.prefix(maximumRowCount)`; `workPrefix = working.prefix(maximumRowCount)`.
  3. For each `id` in `prevPrefix`, stopping once `result.count >= maximumRowCount`:
     - if `workPrefix.contains(id)`: append `id` and remove it from `working` (the item **keeps its slot**);
     - else (the item left the strip, e.g. it went on stage or closed): fill the slot with the **first item of `working` that is not in `prevPrefix`**, then remove it from `working`. Since the old stage group sits at the front of `working`, **the group that left the stage takes the slot of the group that went on stage**. If no such item exists, the slot is dropped.
  4. `result.append(contentsOf: working)` (`FUN_100167dd8`). Remaining groups follow after the visible rows.

`maximumRowCount` only limits how many leading slots are kept stable. It does not hide anything. Visible pile count is decided later by the strip component (`StageManagerRowCountComponent`, `StageManagerStripVisualEffectsModifier.hiddenPiles`). That is **Inferred** from type names; not traced.

ComponentState is then overwritten with `(stripContainerGroupIDs, stageContainerGroupID)` (lines 939-948).

### 3.4 `hiddenContainerGroupIDs` and `exclusiveProcessSerialNumbers` — Observed (lines ~330-937)
`hiddenContainerGroupIDs` is **not** an overflow list. It is only non-empty when `stripParameters.exclusiveProcessSerialNumbers != nil`. In that case, for each strip ID:
- if the group's represented PSNs are disjoint from the exclusive set (`0x1002e820c` = isDisjoint): the group goes to `hidden`;
- otherwise it stays. A `.process(psn)` group is **exploded** into one group per window set, skipping the stage window set. A `.process` window set becomes one `.processWindowSet(psn, .window(wid))` group per window (tag `0x83`). Any other set becomes `.processWindowSet(psn, setID)`. Both are inserted into `containerGroups`.

This is the per-app window exposé in the strip (the separate `exposeStripAssignmentComponent`). That the expose component is the one setting this field is **Inferred**.

## 4. Q4: operations for drag, minimize, close, new window

### 4.1 `ComputeTransientWindowSetOperations` events (`0x100297404`, cases by top 2 bits of tag) — Observed
- **addToStage(W)** (`0x100297810`), e.g. dragging a strip item onto the stage:
  - if the current stage window set is `.userWindowSet(id)`: `[.modify(.addWindowToUserWindowSet(id, W)), .orderWindowFront(W)]`;
  - else, if the stage window set has windows: `[.modify(.createUserWindowSet(UserWindowSet(id: proposedStageUserWindowSetID ?? new, windows: stageSetWindows + [W]))), .orderWindowFront(W)]`. The ID comes from `FUN_100321230` when none is proposed;
  - else (empty stage): `[.orderWindowFront(W)]`.
- **removeFromStage(W)** (`0x100297ad8`), e.g. dragging a stage window to the strip:
  - if W is in a user set: `.modify(.removeWindowFromUserWindowSet(setID, W))`;
  - then, if W was in the stage window set, `.orderWindowFront(next)`, where `next` is another window of the stage window set. Which one is picked was not fully resolved; **Inferred**: the first remaining one.
- **replaceWindowWithWindow(old, new)**: if `old` is in a user set: `[.modify(.addWindowToUserWindowSet(setID, new)), .modify(.removeWindowFromUserWindowSet(setID, old))]`. A replacement window inherits the old window's set membership (Observed).

The drag modifiers (`StageManagerWindowDragModifierComponent`, `StageManagerStripStageWindowDragModifierComponent`) emit `applyOperations([TransientWindowSetOperation])`. Mapping their `stripToStage` / `stageToStrip` directions to addToStage/removeFromStage is **Inferred** from names.

### 4.2 Minimize — partly Observed
- In the assignment, minimized windows become `.minimizedWindow` sets in their group (2.3b). They cannot become the stage window set, and they keep the group in the strip (3.2). (Observed.)
- `StageManagerMiniaturizedWindowsComponent` (`0x1002abce8`) branches on the preference `stageManagerMinimizationBehavior == .dock` (Observed at decompiled lines 122-127). It has a `removeFromUserWindowSet(Set<WindowID>)` action. That minimizing (in the non-dock mode) takes the window out of its user set is **Inferred**: the action name plus the branch layout; the payload was not traced.

### 4.3 Close
Nothing in the assignment special-cases close. A closed window disappears from the windows map, so its `.window` set and possibly its group disappear. If the group was the stage, the next update falls back to the proposal or the first non-minimized group (3.1). If it was in the strip, `stableLeastRecentlyUsed` fills its slot with a new group (3.3). (Observed as a consequence of the algorithm; the close event path itself was not traced.) The proposal for the next key window is covered in 5.

### 4.4 New window — Inferred
`StageManagerAutomaticAddToStageComponent` (`0x100295dd8`):
- Gated by `enableAutomaticNewWindowAddToWindowSet` (Observed, returns `[]` when false).
- Compares the previous and current assignment and `previousSpaceOrderedWindowIDs`.
- For new windows whose app is represented in the previous stage group (PSN hash lookup at lines ~179-198), and that are not persistent windows restored after an app relaunch (`previousBundleIDToTerminatedPersistentWindowID` string-set check, lines ~200-270), it emits `.addToStage(windowID)`. That then becomes 4.1's addToStage, so the window joins the stage's user set.

The gating is Observed. The rest is Inferred: the decompilation is partial, and the `bStack_2b0 < 0x40` test suggests it only applies when the stage group is a `.crossAppSet`. Without this feature, a new window of an app is a new `.window` set in that app's group: it joins the existing group (All at Once) or becomes a new set (One at a Time). It goes on stage when the proposal names it.

## 5. Q5: focus and proposals (`StageManagerProposeKeyAndMainWindowComponent`)

- The assignment's `currentWindowProposal` (`WindowProposal.keyWindow/mainWindow(WindowID?)`) is the only thing that moves the stage (3.1). The stage follows the window the system proposes as key/main. (Observed.)
- The proposal component is an `InputFilteringComponent` with `InputModel { windows, stageWindowIDs }`. It answers `WindowProposalRequest { previousKeyWindow, proposal }` in `0x1002c43a4`:
  - it filters the space's ordered windows to those in `stageWindowIDs`, excluding `previousKeyWindow` (Observed, lines ~60-170);
  - it then prefers a stage window of the same process as the previous key window (PSN compare at lines ~395-415) (**Inferred**);
  - if no stage window is left, it emits `Action.emptyStage(psn?, forProcess)` (**Inferred** from the action case and the empty-list branch).
- It also keeps `expectedRemovedWindows: BidirectionalDictionary<TimerID, WindowID>`, entries removed on events `0x14`/`0x15` (`0x1002c4100`). That looks like a grace period while a closing window disappears (**Inferred**).
- Whether activating an app (Cmd-Tab or a Dock click) proposes that app's most recent window: the request is answered by WindowServer/AppKit's own proposal, and Stage Manager only filters it. I found no code that picks "the app's most recent window" itself. The fallback in 3.1 picks the first group in z-order, which is the frontmost one. **Inferred**: activating an app brings its frontmost window to key, the proposal names it, and the stage switches to that window's group.

## 6. Open items (not verified)
- The exact `WindowDestination` classifier (`0x100313d0c`): the cross-app vs intra-app test and the accessory/sticky criteria.
- The default values of the grouping and replacement-order preferences, and what fills `singleWindowWithPromotion`'s PSN set.
- What sets `stageStyle = .empty`. Likely show-desktop / click-wallpaper / `EmptyStageOverride` (a string exists); not traced.
- The payload of the minimization component's `removeFromUserWindowSet`.

## Rules for Podium

1. Give each app one container group keyed by PSN, holding one window set per window, in z-order. (Observed)
2. In "All at Once", merge an app's loose per-window sets into one app set at the position of its first loose window. Leave user sets and minimized sets separate. (Observed)
3. In "One at a Time", keep one window set per window inside the app's group. (Observed)
4. Put windows of a user set that spans several apps into their own cross-app group. Put a single-app user set inside that app's group as a separate window set. (Observed for group shape; Inferred for the one-app vs many-apps test)
5. Split each minimized window into its own minimized window set inside the same group: after the remaining windows, or before them if the frontmost window was minimized. Never pick a minimized window set as the stage window set. (Observed)
6. Order groups by the z-order of their frontmost window. A group whose app owns the frontmost accessory window (panel) goes first. (Inferred)
7. Make the stage group the first group containing the proposed key/main window. With no match, use the first group in order that has a non-minimized window set. (Observed)
8. When the stage style is empty (desktop), set the stage group and stage window set to nil. (Observed)
9. Make the stage window set the stage group's first non-minimized window set in z-order. (Observed)
10. Remove the stage group from the strip only when it has exactly one window set and that set is not minimized. Otherwise keep it in the strip to show its other or minimized windows. (Observed)
11. With recency ordering (pref "top"), use the group order (minus the stage group, per rule 10) as the strip order. (Observed)
12. With stable LRU ordering (pref "leastRecentUsed"), groups in the first `maximumRowCount` strip slots keep their slots. A vacated slot goes to the previous stage group first, then to the next group that was not visible. Append the remaining groups after. (Observed)
13. Do not use `maximumRowCount` to hide groups. Hidden groups exist only in per-app exposé mode, where groups of other apps are hidden and the exposed app's group is split into one strip item per window. (Observed)
14. When a window is dragged onto the stage, add it to the stage's user set; if the stage has no user set, create one from the stage windows plus the dragged window. Then bring it to front. (Observed)
15. When a window is dragged off the stage, remove it from its user set and bring another window of the stage set to front. (Observed; Inferred for which window)
16. When a window replaces another (same document, new window), it takes the old window's place in its user set. (Observed)
17. With the "auto add new windows" preference on, add a new window of an app already on a cross-app stage set to that set, but not windows restored after an app relaunch. (Inferred)
18. When the key window closes, propose another on-stage window, preferring the same app. If none remains, leave the stage empty for that app. (Inferred)
