# Phase B: 案卷(房间任务面板)+ Thread 绑定 Design

Date: 2026-07-05
Anchor: `2026-07-05-product-northstar-design.md` §5(房间内层次)及其五个已确认落地决策。
Naming: UI copy uses 御案体(chip/面板/详情文案);code identifiers stay functional English.

## Goal

Replace the single-task banner with a multi-task progress chip that opens a per-room task
panel (案卷): pending decisions (待批), active tasks (在办), collapsed done tasks (已结),
with task detail linking to its bound thread (实录).

## What exists (reuse, don't rebuild)

- `TimelineViewState.fetchedStateEvents` + `.fetchStateEvent` action + 0.3s-debounced refresh
  on room activity — the panel's data heartbeat.
- `updateActiveCanvasTask` — currently computes ONE active task; becomes the collector for ALL
  canvas tasks in the room (message items give the initial set; state events give current status).
- `AgentCanvasStepsStateContent` / `AgentChoiceRequestStateContent` parsers.
- `CanvasStepsScreen` — stays as the task-detail screen (already live-updating); gains a
  "查看实录" row.
- choice_request cards in the timeline; `AgentChoiceRequestRoomTimelineItem` carries question +
  resolution state (via `fetchedStateEvents`).
- `RoomFlowCoordinator` canvas-steps push machinery (state machine event, navigation stack).

## Wire format additions (already reserved in the protocol spec)

`io.element.agent.canvas.steps` state event content, all optional:

```json
{ "thread_root_id": "$event_id_of_thread_root", "updated_at": 1783222459000, "priority": 1 }
```

- `thread_root_id` absent → detail screen simply has no 实录 row (graceful degradation).
- `updated_at` used for panel ordering (fallback: undefined order within groups is acceptable V1).
- `priority` parsed but unused in V1 (sorting hook for later).

## Architecture

### 1. Room task collection (TimelineViewModel)

`updateActiveCanvasTask` is replaced by `updateRoomTaskSummary`:

- Collect ALL `AgentCanvasStepsRoomTimelineItem`s in the timeline (not just the last unresolved).
- For each, resolve current status/steps from `fetchedStateEvents` (state event wins over the
  message payload — same precedence as today).
- Collect pending choice requests: `AgentChoiceRequestRoomTimelineItem`s whose resolution state
  (from `fetchedStateEvents`) is absent → pending 请旨.
- Publish into `TimelineViewState.roomTaskSummary`:

```swift
struct RoomTaskSummary: Equatable {
    struct Task: Identifiable, Equatable {
        let eventID: String       // presenting message event (for detail push)
        let taskID: String
        let title: String
        let isResolved: Bool
        let doneStepCount: Int
        let totalStepCount: Int
        let steps: [CanvasStep]   // current steps (state-event-resolved)
        let threadRootEventID: String?
        let updatedAt: Date?
    }
    struct PendingChoice: Identifiable, Equatable {
        let eventID: String       // the choice_request message (for scroll-to)
        let question: String
        var id: String { eventID }
    }
    var activeTasks: [Task] = []      // 在办, updatedAt desc where known
    var doneTasks: [Task] = []        // 已结
    var pendingChoices: [PendingChoice] = []  // 待批
    var isEmpty: Bool { activeTasks.isEmpty && doneTasks.isEmpty && pendingChoices.isEmpty }
}
```

Limitation (accepted, documented): tasks whose message hasn't been paginated into the timeline
aren't collected. Same limitation the banner has today; the cross-room index (差事 tab) reads
state events directly and has no such gap — the panel converges as the timeline loads.

### 2. Progress chip (replaces CanvasTaskBannerView)

`RoomTaskProgressChipView`, shown via the existing `.topBanners` slot:

- Visible when `roomTaskSummary.pendingChoices` or `.activeTasks` is non-empty
  (done-only rooms show no chip; the panel stays reachable — see Open point resolved: chip also
  shows for done-only? No: V1 hides it; 案卷 reachable from 差事 tab row in that case).
- Copy: single active task & no pending → task title + progress (like today);
  otherwise → 「N 件差事在办 · M 件请旨待批」 (M segment omitted when 0).
- Tap → `.tappedRoomTaskChip` view action. **Smart shortcut (决策 6)**: when the summary holds
  exactly one item in total (one active task, no pending choices, no done tasks) the flow pushes
  the task detail directly, skipping the panel; otherwise it presents the panel. Progressive
  disclosure — single-task rooms feel identical to today's banner.

### 3. 案卷 — `AgentTaskPanelScreen` (new MVVM-C quartet)

- Pushed on the room's navigation stack (RoomFlowCoordinator state machine, mirroring the
  existing canvas-steps push).
- Input: the live `TimelineViewModel.Context`? No — panel gets its own lightweight feed:
  coordinator parameters carry a `CurrentValuePublisher<RoomTaskSummary, Never>` exposed by
  TimelineViewModel (panel stays live while pushed).
- Sections (Compound Form):
  1. 【待批】pendingChoices — row: question;tap → action `.focusTimelineEvent(eventID)` →
     RoomFlowCoordinator pops panel and focuses the timeline on that event (reuse the existing
     `focusOnEventID` machinery).
  2. 【在办】activeTasks — row: title | x/y;tap → push `CanvasStepsScreen` (existing detail).
  3. 【已结】doneTasks — collapsed `DisclosureGroup`, same row shape, no badge.
- Empty state:「本案暂无差事」(only reachable via edge cases; chip hidden when empty).

### 4. Task detail additions (CanvasStepsScreen)

- New optional row under the steps:「查看实录」, shown when `threadRootEventID != nil`.
- Tap → coordinator action → RoomFlowCoordinator opens the thread using the existing
  thread-timeline presentation path (same as tapping a thread summary in the timeline).
- Coordinator parameters gain `threadRootEventID: String?`.

### 5. Strings (Untranslated.strings, Chinese values — fork-local)

| key | value |
|---|---|
| `screen_room_task_chip_multi` | `%1$@ 件差事在办` |
| `screen_room_task_chip_pending_suffix` | ` · %1$@ 件请旨待批` |
| `screen_task_panel_title` | `案卷` |
| `screen_task_panel_section_pending` | `待批` |
| `screen_task_panel_section_active` | `在办` |
| `screen_task_panel_section_done` | `已结` |
| `screen_task_panel_empty` | `本案暂无差事` |
| `screen_canvas_steps_view_thread` | `查看实录` |

(Format-string plurals kept simple — Chinese needs no plural forms.)

## Error handling

- State parse failures: skip item, `MXLog.error` (existing pattern).
- Thread jump when thread was deleted/unavailable: existing thread presentation error surface
  (indicator toast), no new handling.
- Panel with stale summary (timeline still paginating): shows what's known; converges via the
  live publisher.

## Testing

- Unit: `RoomTaskSummary` collection logic (message-only task, state-overridden task, pending
  vs resolved choices, done grouping, thread_root_id passthrough) in TimelineViewModel tests;
  panel VM split/actions; chip copy formatting.
- Previews + TestablePreview: chip (single/multi/with-pending), panel (mixed/empty), detail
  with/without 实录 row.
- Device (user): full flow — chip → 案卷 → 详情 → 实录 thread; pending choice scroll-back.

## Out of scope

Thread-side task status bar (reverse direction), kanban, archival policy, 政事 tab, 道 switcher,
goal state event (all Phase C/D). Existing tabs keep current names until C.
