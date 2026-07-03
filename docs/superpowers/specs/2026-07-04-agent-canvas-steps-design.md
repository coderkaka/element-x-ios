# Agent Canvas V1: Step Tracker Design

Status: approved
Date: 2026-07-04

## Problem

The agent-in-Matrix architecture doc (`docs/superpowers/specs/2026-07-01-agent-matrix-canvas-design.md`) locked "timeline = control/audit layer, canvas = native SwiftUI workspace" as the direction, but no canvas content type has been built — only Tier 1 timeline cards (`io.element.agent.turn`, in progress `io.element.agent.choice_request`). This designs and scopes the first canvas content type end-to-end: scenario #9, "live step tracker / task graph," narrowed to a flat checklist (no DAG) for V1.

## Two corrections to the original architecture doc, found while grounding this design in real code

1. **No persistent third navigation column exists, and none should be added for V1.** `NavigationSplitCoordinator` (`NavigationCoordinators.swift:14`) is explicitly documented as "responsible for displaying **2** coordinators side by side" and wraps SwiftUI's two-column `NavigationSplitView(columnVisibility:) { sidebar } detail: { detail }` initializer (`NavigationCoordinators.swift:386-404`) — there is no existing three-column usage anywhere in this codebase to extend. Modifying this shared, widely-used coordinator class to add a third column would be high-blast-radius (it backs settings, room directory browsing, and every other split-view flow, not just chat). V1 canvas is a normal pushed screen instead — works identically on iPhone and iPad, touches no shared navigation infrastructure.
2. **Custom Matrix *state* events (the original doc's `io.element.agent.canvas.*` suggestion) cannot currently be read by this client.** Checked the vendored Rust SDK bindings (`matrix_sdk_ffi.swift`) directly: `StateEventContent` (`matrix_sdk_ffi.swift:40345-40374`) is a closed enum of 19 well-known Matrix state types with no `.other`/unrecognized-type escape hatch — unlike `MessageType.other(msgtype:body:)`, which is exactly how `io.element.agent.turn`/`io.element.agent.choice_request` read their custom content today. A raw state-event *write* exists (`sendStateEventRaw(eventType:stateKey:content:)`, `matrix_sdk_ffi.swift:9187`), but nothing reads a custom state event's content back. Building that read path would mean waiting on new upstream `matrix-rust-sdk`/`matrix-rust-components-swift` bindings — out of scope for an iOS-only plan. **Canvas state is instead carried by a custom *message* type** (`io.element.agent.canvas.steps`), reusing the exact proven pipeline `io.element.agent.turn` and `io.element.agent.choice_request` already established (factory interception of `.other`, content model parsing `originalJSON`/`latestEditJSON`, message editing for updates).

## Decisions

- **V1 content type: flat step list only**, no DAG/dependency graph. Each step has a label and one of three statuses (`pending`/`in_progress`/`done`). This is the narrowest slice of scenario #9 that proves the canvas container end-to-end; a DAG renderer is a separate, later scope if ever needed.
- **Carried by a custom message, not a state event** (see correction #2 above). The agent posts one `io.element.agent.canvas.steps` message per task, then edits that same message to update `status`/`steps` as the task progresses — identical mechanism to `io.element.agent.choice_request`'s `resolved_selection` edit pattern, now proven twice (once by that feature's own implementation, once by its task reviewer independently re-verifying against live `matrix-rust-sdk` source that `latestEditJSON` really does carry a full replacement event).
- **This message also renders a minimal card inline in the timeline** — not hidden. A single-line card ("📋 Task: <title> — View progress") preserves the timeline's role as the audit trail (a record that a task started/was updated exists at that point in the conversation), while the *canvas screen* (reached via the banner) is where the full step list actually renders. This follows the architecture doc's own principle rather than inventing a "hide this from the timeline" mechanism that doesn't exist today.
- **Entry point: a new banner in `RoomScreen`**, added to its existing banner-stacking system (`RoomScreen.swift:75-94`'s `.topBanners([TopBannerLayer(verticalBanners: [TopBannerItem(pinnedItemsBanner, ...), TopBannerItem(liveLocationBanner, ...)]), TopBannerLayer(knockRequestsBanner, ...)])`), following the exact pattern already used by `PinnedItemsBannerView`/`LiveLocationSharingBannerView`/`KnockRequestsBannerView`. Tapping it pushes the canvas screen.
- **V1 shows at most one active task's banner per room** — whichever unresolved (`status: "in_progress"`) `io.element.agent.canvas.steps` message is most recent. No support for multiple simultaneous task banners in one room; a future extension if ever needed, not this scope.
- **Canvas screen is read-only in V1.** No pause/interrupt/redirect controls (that's scenario #10, explicitly out of scope here) — the screen only renders the step list; all writes come from the agent via message edits, none from the client.
- **No cross-room aggregation in V1.** The architecture doc's `(roomID, taskID)` state-keying principle is honored implicitly (the message's own event ID / a `task_id` field in its content already gives every task a stable identity that a future cross-room "Agents hub" — scenario #12 — could query), but nothing in this plan builds that hub. This plan only touches one room's `RoomScreen` at a time.

## Wire Schema

`io.element.agent.canvas.steps`, posted by the agent, edited as the task progresses:

```json
{
  "msgtype": "io.element.agent.canvas.steps",
  "body": "Task: Refactor auth module",
  "task_id": "task-1234",
  "title": "Refactor auth module",
  "status": "in_progress",
  "steps": [
    {"id": "step1", "label": "Read existing code", "status": "done"},
    {"id": "step2", "label": "Generate diff", "status": "done"},
    {"id": "step3", "label": "Wait for approval", "status": "in_progress"},
    {"id": "step4", "label": "Run tests", "status": "pending"}
  ]
}
```

`body` is the required human-readable fallback (matching `io.element.agent.turn`/`io.element.agent.choice_request`'s established convention) for clients that don't recognize the msgtype. `task_id` is a stable identifier separate from the Matrix event ID, present for forward-compatibility with a future cross-room hub (not consumed by anything in this plan). `status` at the top level is `"in_progress"` or `"done"` — the banner's visibility rule is exactly "does an unresolved (`status: "in_progress"`) canvas-steps message exist." Per-step `status` is `"pending"`, `"in_progress"`, or `"done"`. Field names are `snake_case` (`task_id`), matching the established `tool_calls`/`multi_select`/`resolved_selection` convention.

## Components

Following the exact shape established twice already (`io.element.agent.turn`, `io.element.agent.choice_request`):

- **`AgentCanvasStepsRoomTimelineItemContent`** — content model, parsing `task_id`/`title`/`status`/`steps` from `originalJSON`/`latestEditJSON` (reusing the same dual-shape defensive parsing `AgentChoiceRequestRoomTimelineItemContent` established and had independently verified against real `matrix-rust-sdk` source this session).
- **`AgentCanvasStepsRoomTimelineItem`** — timeline item, registered through the same extension points as `.agentTurn`/`.choiceRequest`.
- **`AgentCanvasStepsRoomTimelineView`** — the minimal inline timeline card (title + "View progress" tap target), wrapped in `TimelineStyler`.
- **`CanvasTaskBannerView`** — new `RoomScreen` banner, modeled on `PinnedItemsBannerView`'s shape (a view + a state struct + a tap action), added to the existing `.topBanners([...])` stack.
- **A new pushed screen** for the canvas itself (exact MVVM-C naming — e.g. `CanvasStepsScreen`/`CanvasStepsScreenViewModel`/`CanvasStepsScreenCoordinator` — to be finalized during planning against this codebase's `createScreen.sh` template convention) rendering the full step list for one task, reading the same `AgentCanvasStepsRoomTimelineItemContent` the inline card already parsed.

## Open implementation question, to be resolved during planning (not blocking this design)

`RoomScreenViewModel`'s existing `pinnedEventsBannerState` is populated from a *curated* set of pinned event IDs (`roomInfo.pinnedEventIDs`, `RoomScreenViewModel.swift:343`), not a scan over all visible timeline items — a different data source than what the canvas banner needs ("is there an unresolved `.canvasSteps` item anywhere in this room's currently-loaded timeline"). The exact mechanism for `RoomScreenViewModel` (or `TimelineViewModel`, if that's the more appropriate owner) to observe this reactively needs to be grounded in real code during the implementation plan, the same way every other task this session read real files before locking in code — this is deliberately left open here rather than guessed at the design level.

## Error Handling

- **Malformed/unparseable `steps`**: the inline timeline card falls back to `body`-only rendering (no step list), same graceful-degradation posture as `io.element.agent.turn`'s malformed `tool_calls` and `io.element.agent.choice_request`'s malformed `options`.
- **Old/non-Element clients**: see the `body` fallback text for the inline card; no canvas screen exists for them (expected — canvas is additive UI, not a requirement to understand the room).
- **Canvas screen opened for a task with no still-loaded timeline item** (e.g. very old task, timeline not paginated back far enough): out of scope for V1 — the banner only ever links to a task whose message is already in the currently-loaded timeline (the same one that made the banner visible), so this can't happen via the only entry point this plan builds.

## Explicitly Out of Scope

- DAG/dependency-graph rendering (flat list only).
- Multiple simultaneous task banners in one room.
- Any write/interaction from the canvas screen (pause/interrupt/redirect — scenario #10).
- Cross-room aggregation ("Agents hub" — scenario #12).
- Native diff/artifact view (scenario #8) — a separate future canvas content type, not this one.

## Testing

Same shape as the prior two message types: unit tests for `AgentCanvasStepsRoomTimelineItemContent`'s JSON parsing (well-formed, missing/malformed `steps`, edited-with-updated-status via both hypothesized-then-confirmed edit shapes — reuse the now-confirmed-correct assumption directly this time, no need to re-litigate it), `TestablePreview`-driven snapshot/accessibility tests for `AgentCanvasStepsRoomTimelineView` (the inline card) and the new canvas screen (multiple steps in mixed statuses), and a test for whatever view model ends up owning the banner-visibility computation (resolved during planning per the open question above).
