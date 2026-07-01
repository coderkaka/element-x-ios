# Agent-in-Matrix Interaction Design: Chat as Backbone, Canvas as Workspace

Status: draft, pending user review
Date: 2026-07-01

## Problem

An AI agent (not a webhook/chat bot — a Claude/GPT-class agent capable of multi-step tool use) is being integrated as a Matrix room participant. Plain text messages are the current interaction surface. This doc proposes the interaction architecture and a layered menu of future-facing scenarios beyond simple chat, so product direction can be set before capabilities are built.

Scope: interaction architecture + scenario catalog. Not a build plan for any single scenario — that comes later, per scenario, once one is picked to implement.

## Architecture

**Decision: chat timeline is the control/audit layer; a native SwiftUI canvas is the workspace for rich agent state.**

Why: the Matrix room gives identity, permissions, E2E encryption, multi-device sync, and history for free. But its timeline is an append-only, linear event stream built for async human chat — it doesn't hold up under continuously-updating state (progress, editable artifacts, multi-step tool traces). Forcing that into the timeline produces clutter. A separate canvas, reserved for exactly that class of state, keeps the timeline as a clean record of "what happened" while the canvas is "what's happening / what's being worked on right now." This mirrors the pattern used by Claude Artifacts, ChatGPT Canvas, and Slack App Home.

Canvas is **native SwiftUI**, not a Matrix Widget (iframe/WebView). Every new agent content type costs an app release, but native gesture/animation/accessibility and Compound design-system consistency are worth that cost over WebView sandboxing and visual inconsistency.

**Content model** extends the existing timeline extensibility pattern rather than inventing a new one. Today, a new message type flows:

```
Rust SDK event → RoomTimelineItemFactory (switch on content type)
→ concrete RoomTimelineItem (e.g. LocationRoomTimelineItem)
→ RoomTimelineItemViewState case → dedicated SwiftUI view (e.g. LocationRoomTimelineView)
```
(`ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemFactory.swift:28-48`, `LocationRoomTimelineItem.swift:11-31`, `RoomTimelineItemView.swift:65-66`)

Unknown/unparseable events already degrade gracefully to `UnsupportedRoomTimelineItem` (`RoomTimelineItemFactory.swift:49-52`, `:750-764`) — a warning-icon fallback view. This means new agent event types are safe to ship incrementally: older clients show a graceful "unsupported" fallback instead of breaking.

The canvas follows the same shape: a custom Matrix event type (e.g. `io.element.agent.canvas.*`) is parsed into a typed `CanvasState` and dispatched to a dedicated SwiftUI view, the same way `.location` dispatches to `LocationRoomTimelineView` — except the destination is the canvas panel, not an inline timeline cell.

**Placement — Approach C (room-scoped now, cross-room-aggregable later):**

- V1 ships as a **room-scoped detail pane**, reusing `NavigationSplitCoordinator`'s existing sidebar/detail split (`NavigationCoordinators.swift:14-327`, `setDetailCoordinator():192`) — the same mechanism `ChatsTabFlowCoordinator` already uses to show a room's timeline in the detail column on iPad, collapsing to a pushed screen on iPhone. Low risk, matches the current "you're in a room talking to an agent" mental model, no new navigation plumbing.
- Underlying state is **not** modeled as room-private. It's keyed `(roomID, taskID) → CanvasState`, so it can be queried across rooms later without a rewrite.
- A future cross-room "Agents" hub is a straightforward addition on top of this: a new top-level tab in `NavigationTabCoordinator` (`NavigationTabCoordinator.swift:13-298`, tab registration in `UserSessionFlowCoordinator.swift:22-127`), aggregating `CanvasState` across rooms the way `SearchScreen` already aggregates room summaries across rooms via `RoomSummaryProvider` (`SearchScreenViewModel.swift:31-46`). That precedent — a cross-room aggregation screen already exists and is wired as a tab — de-risks this future step.

## Scenario Catalog

Layered by how much new infrastructure each needs. Tier 1 needs nothing beyond what exists today. Tier 2 needs the canvas (above). Tier 3 is the "represents the future" tier — cross-room, ambient, OS-level.

### Tier 1 — near-term, existing primitives only

1. **Dedicated agent-turn message type** — instead of raw text, agent replies render as a new `EventBasedMessageTimelineItemContentType` case with a collapsible reasoning/tool-call summary, following the exact `.location`/`.poll` pattern. Old clients see the `Unsupported` fallback, not garbage.
2. **Inline tool-call chips** — small tappable badges in the message body ("Read file X", "Ran search") using existing Compound badge/`ListRow` tokens — expandable detail, no new panel needed.
3. **Pinned live task summary** — the agent keeps one pinned message as its current plan/status, updated via message edit (already supported) instead of spamming the timeline with progress updates.
4. **Typing indicator = "agent is working"** — map real agent work state onto the existing `m.typing` ephemeral event; zero new UI.
5. **Reactions as approve/reject** — user reacts 👍/👎 (or a custom emoji) to gate the agent's next step; reuses existing reaction UI and aggregation, agent listens for the reaction event. Cheapest possible human-in-the-loop control.
6. **Threads for sub-tasks** — each parallel tool-call chain gets its own thread, keeping the main timeline readable; reuses existing thread UI as-is.

### Tier 2 — canvas-based, per Approach C

7. **Room-scoped canvas panel** — live plan/progress view in the detail pane, driven by custom state events, following the `RoomTimelineItemFactory` extension pattern above.
8. **Native diff/artifact view** — code or document edits shown as a native before/after diff (mini code review) in the canvas; approval writes back as a Matrix event, so it's encrypted and auditable like everything else in the room.
9. **Live step tracker / task graph** — canvas renders a checklist or DAG of steps, each backed by a state event — multi-device sync comes free: open the same progress on phone and iPad.
10. **Pause / interrupt / redirect controls** — canvas exposes controls that write control-plane events into the room, so "who paused what, when" is part of the auditable history, not just ephemeral client state.
11. **Structured input requests** — the agent posts a form (pick one of N, fill a field) as native Compound form components; the response is a normal event, so it degrades to plain text on clients that don't understand the schema yet.

### Tier 3 — future-direction: cross-room, ambient, OS-level

12. **"Agents" hub tab** — cross-room task center aggregating all in-flight/completed agent tasks (the cross-room aggregation step described in Architecture), in the spirit of Copilot Workspace's task list or Linear's agent sessions.
13. **Space-scoped agent** — one agent acting across every room in a Space (dovetails with the just-shipped space tab bar) — e.g. an IT-support agent operating across many ticket-rooms in one space.
14. **Live Activity / Dynamic Island** — a long-running agent task surfaces as an iOS Live Activity; tapping deep-links via `AppRoute` straight into its canvas.
15. **Structured push notifications** — NSE-decrypted notifications render a mini summary with actionable buttons (Approve/Deny) instead of "agent replied", via a notification content extension.
16. **Glanceable Home/Lock Screen widget** — a pinned agent task's live status via WidgetKit, reading last-synced `CanvasState` without opening the app.
17. **Multi-agent presence in one room** — several agents in a room shown with distinct avatar/border colors, each owning a tab within the same canvas panel — makes planner/coder/reviewer-style multi-agent workflows visually legible instead of a wall of interleaved bot messages.
18. **Cross-device handoff for free** — because `CanvasState` is keyed by `(roomID, taskID)` and synced via Matrix events from day one, starting a task on iPhone and picking up approval on iPad (or Element Web, eventually) requires no extra work — it falls out of the architecture decision above.
19. **Voice-first delegation via existing VoIP/CallKit** — the agent joins an active call as a participant; the canvas becomes the "shared screen" companion to a voice-driven task session.

## Open questions (not yet decided)

- Exact custom event type namespace/schema for canvas state (`io.element.agent.canvas.*` is a placeholder).
- Whether Tier 3's "Agents" hub ships as its own tab or nests under the space tab bar's model — audited as feasible either way, not chosen yet.
- Which single scenario to build first once this catalog is reviewed.

## Out of scope

- Any specific agent's capabilities/backend (this is a client-side interaction design).
- Matrix Widget (iframe) infrastructure — considered and explicitly rejected in favor of native SwiftUI (see Architecture).
