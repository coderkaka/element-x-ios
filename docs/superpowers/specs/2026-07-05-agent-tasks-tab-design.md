# Agent Tasks Tab (跨房间任务索引) Design

Date: 2026-07-05
Status: Approved direction (decisions made interactively across 2026-07-03/04 sessions); V1 scope locked here.

## Goal

A new bottom tab that aggregates agent task state across all joined rooms, so the app starts
functioning as a general goal/progress-management platform (one goal = one Matrix room) rather
than a pure chat client. This is V1 of the "workspace" direction: a read-only cross-room task
list with navigation into the owning room.

## Prior decisions this builds on (already user-approved)

- One goal = one Matrix room; task data lives in that room.
- Task state lives in `io.element.agent.canvas.steps` **room state events** keyed by `task_id`
  (2026-07-05 architecture rewrite, verified end-to-end on device).
- The local SDK fork syncs these state event types via sliding sync `required_state`
  (commit 86916c2), so reads are local-store hits and updates arrive with sync.
- `Room::get_state_events_raw(event_type) -> [String]` (same commit) enumerates all tasks in a
  room without knowing state keys up front.
- Tab renaming (聊天/空间 naming) is explicitly deferred — needs the user's naming decisions.
  V1 adds the new tab without renaming the existing ones.

## Wire format

State event `io.element.agent.canvas.steps`, state key = `task_id`, content:

```json
{
  "title": "Refactor auth module",     // optional; new — agents should start including it
  "status": "in_progress",             // "in_progress" | "done" (unknown values treated as unresolved)
  "steps": [ {"id": "s1", "label": "…", "status": "pending|in_progress|done|<other>"} ]
}
```

`title` is a **protocol addition** for the index (previously title only lived in the original
message, which the index never reads). Clients fall back to showing `task_id` when absent.
The existing per-room card/banner keep reading title from the message and are unaffected.

## Architecture

Three units, following existing app patterns:

### 1. `ClientProxy.getRoomStateEventsRaw(roomID:eventType:)`

`ClientProxyProtocol` gains:

```swift
func getRoomStateEventsRaw(roomID: String, eventType: String) async -> Result<[String], ClientProxyError>
```

Implementation calls `client.getRoom(roomId:)` and the SDK room's `getStateEventsRaw(eventType:)`
directly. Deliberately **not** on `JoinedRoomProxy`: building a `JoinedRoomProxy` spins up a live
timeline per room, far too heavy for iterating N rooms.

### 2. `AgentTaskIndexService` (`ElementX/Sources/Services/AgentTasks/`)

- Consumes `RoomSummaryProviderProtocol.roomListPublisher` (the existing cross-room mechanism)
  and the new `ClientProxy` method.
- On room list updates (debounced 1s), enumerates `io.element.agent.canvas.steps` state events
  for every joined room in the summary list and parses them into:

```swift
struct AgentTaskSummary: Identifiable, Equatable {
    let id: String            // roomID + task_id
    let roomID: String
    let roomName: String      // from RoomSummary
    let taskID: String
    let title: String?        // nil → UI shows taskID
    let isResolved: Bool
    let doneStepCount: Int
    let totalStepCount: Int
}
```

- Publishes `tasksPublisher: CurrentValuePublisher<[AgentTaskSummary], Never>`, unresolved first,
  then resolved; stable order within groups (room order from the summary provider).
- Protocol + Sourcery mock like every other service.

### 3. `AgentTasksScreen` (MVVM-C, new `HomeTab.tasks`)

- Standard screen quartet (Models/VM protocol/VM/View) + coordinator, template-conformant.
- Sections: 进行中 / 已完成. Row: title (or taskID), room name, progress `done/total`,
  checkmark when resolved. Empty state text when no tasks anywhere.
- Tap row → coordinator action `presentRoom(roomID:)` → `UserSessionFlowCoordinator` routes with
  the existing room-presentation machinery (same as tapping a room in the chats tab).
- Tab: new `HomeTab.tasks` case in `UserSessionFlowCoordinator`, `NavigationSplitCoordinator`
  wrapper like the existing tabs, icon `\.listBulleted` (or closest Compound equivalent),
  untranslated title "Tasks" (`UntranslatedL10n`), positioned between Chats and Spaces.

## Error handling

- Per-room state read failures are logged and skipped (one bad room must not empty the whole list).
- Unparseable state event JSON → skipped, `MXLog.error`.
- Rooms without any task state contribute nothing (the overwhelmingly common case, zero cost —
  local store lookup only).

## Testing

- Unit tests: state-content parsing (title fallback, unknown status), aggregation ordering,
  per-room failure isolation — with mocked ClientProxy/RoomSummaryProvider.
- Previews + `TestablePreview` for the screen (empty, mixed, all-done states).
- Full-suite compile + unit test run on the Mac; **no device verification tonight** (user tests
  in the morning).

## Out of scope for V1

- Tab renaming, kanban/board layout, task creation from the tab, spaces-level grouping,
  choice_request aggregation (tasks only), live per-second updates (room-list-driven refresh
  is enough).
