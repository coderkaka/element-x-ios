# Phase B: Room Task Panel (案卷) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-task banner with a multi-task progress chip opening a per-room task panel (待批/在办/已结), task detail gaining a thread jump (实录), per `docs/superpowers/specs/2026-07-05-phase-b-task-panel-design.md`.

**Architecture:** `TimelineViewModel` collects a `RoomTaskSummary` (all canvas tasks + pending choices, state-event-resolved); a chip view replaces `CanvasTaskBannerView`; a new `AgentTaskPanelScreen` renders the summary live; `RoomFlowCoordinator` gains panel presentation with a single-item smart shortcut and a pending-choice focus-back path; `CanvasStepsScreen` gains a 查看实录 row.

**Tech Stack:** Swift 6.2 / SwiftUI / Combine, Compound, Sourcery mocks, Swift Testing.

## Global Constraints

- **No local Swift toolchain here.** Per-task loop: edit on Linux → commit → `git push coderkaka feature/space-tab-bar` → `ssh -i ~/.ssh/id_ed25519_kaka zhangqiong@mac-mini.tail2edbaa.ts.net 'cd ~/Code/element-x-ios && git pull --ff-only origin feature/space-tab-bar'` → on the Mac regenerate as needed (`~/.local/bin/xcodegen` for new files; `~/.local/bin/sourcery --config Tools/Sourcery/AutoMockableConfig.yml` for protocol changes, plus `PreviewTestsConfig.yml`/`TestablePreviewsDictionary.yml`/`AccessibilityTests.yml` for new previews) → build `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -configuration Debug -destination 'platform=iOS,id=A0B22EAF-7313-5DBF-B829-A1812C1CCD82' CODE_SIGN_STYLE=Automatic` (**success = zero `error:` lines; the CodeSign `errSecInternalComponent` failure is expected and NOT an error**) → tests `xcodebuild test -scheme UnitTests -destination 'platform=iOS Simulator,id=0D2C8E22-14AF-48A3-A7CE-552709547033' -only-testing:...` → commit Mac-side generated changes on the Mac, push, pull back.
- MatrixRustSDK resolves to local `../matrix-rust-sdk-pinned` on the Mac — never touch package references.
- **No device installs** — user verifies later.
- UI copy is Chinese 御案体 via `Untranslated.strings` (base/en file — fork-local decision); keys and exact values are in the spec §5 table. Code identifiers stay functional English.
- Wire fields snake_case; previews use `PreviewProvider` + `TestablePreview`; SwiftFormat pre-commit hook on the Mac may abort once with auto-fixes — re-stage and retry.
- Do NOT run the PreviewTests scheme (snapshot baselines are recorded by the user on-device later); regenerating the preview-test sources via Sourcery IS required for new previews.

---

### Task 1: RoomTaskSummary collection layer

**Files:**
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentCanvasStepsRoomTimelineItemContent.swift` (extend `AgentCanvasStepsStateContent`)
- Create: `ElementX/Sources/Screens/Timeline/RoomTaskSummary.swift`
- Modify: `ElementX/Sources/Screens/Timeline/TimelineModels.swift`
- Modify: `ElementX/Sources/Screens/Timeline/TimelineViewModel.swift`
- Test: `UnitTests/Sources/AgentCanvasStepsRoomTimelineItemContentTests.swift` (extend), `UnitTests/Sources/TimelineViewModelTests.swift` (extend — check the existing file name first; if timeline VM tests live elsewhere, put the new suite in a new `RoomTaskSummaryCollectionTests.swift`)

**Interfaces:**
- Consumes: `AgentCanvasStepsRoomTimelineItem`, `AgentChoiceRequestRoomTimelineItem`, `TimelineViewState.fetchedStateEvents`, `AgentChoiceRequestStateContent` (all existing).
- Produces: `RoomTaskSummary` (exact struct from spec §Architecture-1, verbatim — including `Task`/`PendingChoice` nested types and `isEmpty`); `TimelineViewState.roomTaskSummary: RoomTaskSummary = .init()`; extended `AgentCanvasStepsStateContent` with `title: String?`, `threadRootEventID: String?`, `updatedAt: Date?`.

- [ ] **Step 1:** Extend `AgentCanvasStepsStateContent`: parse optional `title`, `thread_root_id` → `threadRootEventID`, `updated_at` (ms since epoch) → `updatedAt: Date?`. Keys via `CodingKeys` snake_case. Extend its unit tests: fields present, fields absent (nil), `updated_at` conversion.
- [ ] **Step 2:** Create `RoomTaskSummary.swift` with the spec's struct verbatim (nonisolated, like sibling models).
- [ ] **Step 3:** In `TimelineModels.swift`: replace `activeCanvasTask` tuple with `var roomTaskSummary = RoomTaskSummary()` (keep the doc comment style). Keep the `tappedCanvasTaskBanner` view action name for now (renamed in Task 4).
- [ ] **Step 4:** In `TimelineViewModel.swift`: replace `updateActiveCanvasTask(timelineItems:)` + `isCanvasTaskResolved` with `updateRoomTaskSummary(timelineItems:)`:
  - Canvas tasks: for each `AgentCanvasStepsRoomTimelineItem` (skip items without `id.eventID`), kick `fetchStateEvent` (existing) and resolve current fields — state event (via `fetchedStateEvents[StateEventKey(eventType: AgentCanvasStepsRoomTimelineItemContent.msgType, stateKey: taskID)]`) wins over message content for `title`/`isResolved`/`steps`/`threadRootEventID`/`updatedAt`; message payload is the fallback. `doneStepCount = steps.count(where: { $0.status == .done })`.
  - Pending choices: for each `AgentChoiceRequestRoomTimelineItem` with an `eventID`, kick `fetchStateEvent(eventType: AgentChoiceRequestRoomTimelineItemContent.msgType, stateKey: eventID)`; pending = no parseable `AgentChoiceRequestStateContent` in the cache. `question` falls back to `content.body` when empty.
  - Sort activeTasks by `updatedAt` descending, nils last; doneTasks same. Assign `state.roomTaskSummary`.
  - Update the two existing call sites (`updateTimelineItems` and the post-fetch refresh in `fetchStateEvent`) to call the new name. Fix the `tappedCanvasTaskBanner` handler to guard on `!state.roomTaskSummary.isEmpty` and keep sending the existing `.presentCanvasSteps` action for the first active task **temporarily** (Task 4 replaces this routing; the app must still compile and behave banner-like in between).
- [ ] **Step 5:** Unit tests for the collection: message-only task; state-overridden task (title/steps/threadRootEventID from state win); resolved vs pending choice; done grouping; updatedAt ordering; summary empty when no agent items.
- [ ] **Step 6:** Mac loop: build + `-only-testing:UnitTests/AgentCanvasStepsRoomTimelineItemContentTests -only-testing:UnitTests/<the new/extended timeline suite>`; commit (`Collect a full per-room task summary instead of a single active canvas task`), push, pull back.

---

### Task 2: Progress chip

**Files:**
- Create: `ElementX/Sources/Screens/RoomScreen/View/RoomTaskProgressChipView.swift`
- Delete: `ElementX/Sources/Screens/RoomScreen/View/CanvasTaskBannerView.swift`
- Modify: `ElementX/Sources/Screens/RoomScreen/View/RoomScreen.swift` (the `canvasTaskBanner` computed var at ~line 150)
- Modify: `ElementX/Resources/Localizations/en.lproj/Untranslated.strings` (+ regenerate SwiftGen on Mac)

**Interfaces:**
- Consumes: `TimelineViewState.roomTaskSummary` (Task 1); sends existing `.tappedCanvasTaskBanner` view action.
- Produces: `RoomTaskProgressChipView(summary:onTap:)` displayed in `RoomScreen`'s `.topBanners` slot.

- [ ] **Step 1:** Build `RoomTaskProgressChipView`: hidden when `summary.pendingChoices.isEmpty && summary.activeTasks.isEmpty`; single active task + no pending → task title + `x/y` (visually equivalent to the old banner — reuse its layout as the starting point, it's being deleted so copy freely); otherwise `screen_room_task_chip_multi` (+ `_pending_suffix` when pending > 0), using `UntranslatedL10n` accessors. Previews (single / multi / with-pending) + `TestablePreview`.
- [ ] **Step 2:** Replace the `canvasTaskBanner` var in `RoomScreen.swift` to construct the chip from `timelineContext.viewState.roomTaskSummary`; delete `CanvasTaskBannerView.swift`.
- [ ] **Step 3:** Add the two chip string keys (spec §5), regenerate SwiftGen (Mac: `swiftgen config run --config Tools/SwiftGen/swiftgen-config.yml`), xcodegen (file add/remove), sourcery preview configs.
- [ ] **Step 4:** Mac loop: build; no new unit tests (view-only — previews cover it); commit (`Replace the canvas task banner with a multi-task progress chip`), push, pull back. Note: deleting `CanvasTaskBannerView` orphans its recorded snapshots — delete stale `__Snapshots__` files for it on the Mac if the preview-test regeneration complains; otherwise leave for the user's re-record pass.

---

### Task 3: 案卷 — AgentTaskPanelScreen

**Files:**
- Create: `ElementX/Sources/Screens/AgentTaskPanelScreen/AgentTaskPanelScreenModels.swift`
- Create: `ElementX/Sources/Screens/AgentTaskPanelScreen/AgentTaskPanelScreenViewModelProtocol.swift`
- Create: `ElementX/Sources/Screens/AgentTaskPanelScreen/AgentTaskPanelScreenViewModel.swift`
- Create: `ElementX/Sources/Screens/AgentTaskPanelScreen/AgentTaskPanelScreenCoordinator.swift`
- Create: `ElementX/Sources/Screens/AgentTaskPanelScreen/View/AgentTaskPanelScreen.swift`
- Modify: `Untranslated.strings` (panel keys from spec §5)
- Test: `UnitTests/Sources/AgentTaskPanelScreenViewModelTests.swift`

**Interfaces:**
- Consumes: `RoomTaskSummary` (Task 1). Coordinator parameters: `summaryPublisher: CurrentValuePublisher<RoomTaskSummary, Never>`.
- Produces: `AgentTaskPanelScreenCoordinatorAction { case presentTaskDetail(task: RoomTaskSummary.Task); case focusTimelineEvent(eventID: String) }`; ViewModel mirrors with same-shape `ViewModelAction`. Task 4 wires both.

- [ ] **Step 1:** Quartet mirroring `AgentTasksScreen` (the closest precedent, built two days ago — read it first). ViewState holds the three arrays split from the live summary; ViewActions `taskTapped(RoomTaskSummary.Task)` / `choiceTapped(eventID: String)`.
- [ ] **Step 2:** View: Compound Form; section 待批 (rows: question, `kind: .button` → choiceTapped), section 在办 (title | `x/y` details → taskTapped), section 已结 inside a collapsed `DisclosureGroup` (verify Compound plays well inside Form — if `DisclosureGroup` fights `.compoundList()`, an always-visible section with a `screen_task_panel_section_done` header is the accepted fallback; note the substitution). `navigationTitle` = `screen_task_panel_title`. Empty state per spec. Previews: mixed / empty / pending-only.
- [ ] **Step 3:** Strings (5 panel keys), SwiftGen, xcodegen, sourcery (all configs — new protocol + new previews).
- [ ] **Step 4:** VM tests: summary → three-way split updates live via publisher; both tap actions forward. `deferFulfillment` pattern.
- [ ] **Step 5:** Mac loop: build + `-only-testing:UnitTests/AgentTaskPanelScreenViewModelTests`; commit (`Add AgentTaskPanelScreen (案卷) listing the room's tasks and pending choices`), push, pull back.

---

### Task 4: Flow wiring — panel presentation, smart shortcut, thread jump

**Files:**
- Modify: `ElementX/Sources/Screens/Timeline/TimelineModels.swift` + `TimelineViewModel.swift` (action rename/reshape)
- Modify: `ElementX/Sources/FlowCoordinators/RoomFlowCoordinatorStateMachine.swift` (new `taskPanel` state/event, keep `canvasSteps`)
- Modify: `ElementX/Sources/FlowCoordinators/RoomFlowCoordinator.swift`
- Modify: `ElementX/Sources/Screens/CanvasStepsScreen/*` (threadRootEventID param + 实录 row + action)
- Modify: `Untranslated.strings` (`screen_canvas_steps_view_thread`)
- Test: extend the Task 1 timeline suite for the new action; full `UnitTests` suite run

**Interfaces:**
- Consumes: everything above. Thread presentation: the existing `.thread(threadRootEventID:previousState:)` state machine event/state (RoomFlowCoordinatorStateMachine.swift:63) — jump via the same `stateMachine.tryEvent` path `displayThread` uses (find its handler and mirror it).
- Produces: `TimelineViewModelAction.presentTaskPanel(summaryPublisher:)`? No — keep it simple: rename `.presentCanvasSteps(eventID:taskID:)` → keep as-is for detail pushes, and ADD `.presentTaskPanel`. The chip handler in `TimelineViewModel` implements 决策 6: exactly-one-item summary → send `.presentCanvasSteps(first task)`; otherwise `.presentTaskPanel`.

- [ ] **Step 1:** `TimelineViewModelAction`: add `case presentTaskPanel`. Chip tap handler (`tappedCanvasTaskBanner` — rename the view action to `tappedRoomTaskChip` across VM/RoomScreen) implements the smart shortcut per spec 决策 6 (single active task, no pending, no done → detail; else panel).
- [ ] **Step 2:** State machine: add `case taskPanel(previousState: State)` + `presentTaskPanel`/`dismissTaskPanel` events, transitions mirroring `canvasSteps` (RoomFlowCoordinatorStateMachine.swift:80 and its transition table entries — copy the shape exactly). **Adding enum cases may break exhaustive switches — fix every compile error the Mac build surfaces, mirroring how `canvasSteps` is handled in each.**
- [ ] **Step 3:** `RoomFlowCoordinator`: handle the new action → tryEvent; `presentTaskPanel(animated:)` builds `AgentTaskPanelScreenCoordinator` with a summary publisher. Expose that publisher from the timeline: `TimelineViewModel` (protocol + impl) gains `var roomTaskSummaryPublisher: CurrentValuePublisher<RoomTaskSummary, Never>` (back it with a CurrentValueSubject updated in `updateRoomTaskSummary`; regenerate mocks). Panel actions: `.presentTaskDetail(task)` → push canvas steps via the existing `presentCanvasSteps` machinery (pass the task's eventID/taskID — but prefer constructing the detail directly from `RoomTaskSummary.Task` to avoid the timeline-item lookup failing for tasks whose message scrolled out: change `presentCanvasSteps(eventID:taskID:)` to accept the task's data when coming from the panel; keep the old lookup path for legacy callers if any remain). `.focusTimelineEvent(eventID)` → pop panel (`navigationStackCoordinator.pop()`) then `handleAppRoute(.childEvent...)`? — NO: reuse the timeline focus: send `.focusOnEventID` isn't a flow action; find how `FocusEvent` room routes work (`.room` state with focusEvent, RoomFlowCoordinator.swift:42 `case thread(rootEventID:focusEventID:)` suggests a focus mechanism exists) and use the same path the search-result → event navigation uses. If that spelunking exceeds budget, V1 fallback: pop the panel and send the timeline view action `.focusOnEventID(eventID)` through the timeline VM (it exists as a `TimelineViewAction` at TimelineModels.swift:92) — document which path was taken.
- [ ] **Step 4:** `CanvasStepsScreen`: coordinator params + VM gain `threadRootEventID: String?`; View shows a `ListRow`「查看实录」 when non-nil; action bubbles to `RoomFlowCoordinator` which fires the thread state machine event (mirror `displayThread`'s handler). Update the RoomFlowCoordinator call site(s) to pass `threadRootEventID` from the summary task (nil for the legacy timeline-item path).
- [ ] **Step 5:** Strings + SwiftGen + sourcery (mocks for the changed TimelineViewModel protocol) + xcodegen.
- [ ] **Step 6:** Tests: smart-shortcut routing (one-item → presentCanvasSteps, multi → presentTaskPanel) in the timeline suite; extend canvas-steps VM tests if its init changed shape. Then **full UnitTests suite** on the Mac (known pre-existing failures: 10 Chinese-locale string mismatches + 3 documented non-locale ones — anything NEW must be investigated honestly).
- [ ] **Step 7:** Commit (`Wire the task panel flow with smart shortcut and thread jump`), push, pull back.
