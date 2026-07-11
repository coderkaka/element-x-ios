# Agent Structured Choice Requests: Design

Status: approved
Date: 2026-07-04

## Problem

Interacting with an agent in a Matrix room today means typing free text for every response, including when the agent is really just asking "pick one of these N things" (which environment to deploy to, approve/reject a plan, choose a branch). Typing is slower and more error-prone than tapping a button, and the agent has to parse free text back into intent instead of reading a deterministic choice.

This is scenario #11 ("Structured input requests") from `docs/superpowers/specs/2026-07-01-agent-matrix-canvas-design.md`'s Tier 2 catalog, narrowed to single/multi-select button choices only (no free-text form fields — that remains out of scope, deferred if ever needed). Narrowing the scope this way means the feature needs no canvas: it fits entirely within the existing timeline-card extensibility pattern already proven by `io.element.agent.turn` (`docs/superpowers/plans/2026-07-02-agent-turn-message-type.md`), so it doesn't depend on the (currently unbuilt) canvas architecture. It does, however, establish a request/response wire pattern that later canvas-based scenarios (e.g. #9 step tracker, #10 pause/interrupt controls) can reuse once canvas ships.

## Decisions

- **Scope: single/multi-select buttons only.** No free-text input fields. If free-text structured input is needed later, it's a separate follow-on scope, not bundled here.
- **No canvas.** Pure inline timeline card, same architecture tier as the already-shipped `io.element.agent.turn`.
- **No per-user targeting/authorization.** Any member of the room can answer — deliberately not restricted to whoever triggered the agent task. (This was weighed against reusing Matrix's native `m.poll` type, which has the same "anyone can respond" semantics; a poll was rejected in favor of a bespoke message type for a different reason — polls are visually and conceptually a room-wide survey with live tallies, not a one-shot directed prompt — but the "who can answer" behavior itself ended up the same by deliberate choice, not oversight.)
- **Multiple different answers: card shows the most recent.** If several room members answer differently, the agent (not the client) decides what to do with that and edits the request card to reflect whichever answer it treats as authoritative. The client has no multi-answer-aggregation logic of its own.
- **The answer is a normal `m.text` reply, not a new message type.** A dedicated response message type was considered and rejected: unless the client explicitly recognizes a custom `msgtype`, it renders as `UnsupportedRoomTimelineItem` (the existing "unsupported message" fallback) — the exact trap `io.element.agent.turn` had to build interception machinery to avoid. Since a user's answer only needs to look like a normal chat reply (no bespoke rendering is useful for one's own answer), sending plain `m.text` with a human-readable body sidesteps the problem entirely: it renders correctly on every Matrix client, old or new, Element or otherwise, with zero new client code.
- **No extra custom JSON field on the reply — the `body` text itself is the only carrier, in a fixed, client-generated format.** An earlier version of this design proposed bolting a machine-readable `io.element.agent.choice_selected` field onto the reply event, alongside its human-readable `body`. Verified against the current SDK bindings (`TimelineProxy.swift`'s `sendMessage`/`buildMessageContentFor`) that this isn't achievable: plain-text replies are built via the Rust SDK's typed `RoomMessageEventContentWithoutRelation` (`messageEventContentFromMarkdown`/`messageEventContentFromHtml` plus `.withMentions`), which exposes no way to attach an arbitrary extra field from the Swift layer — doing so would require a `matrix-rust-sdk` upstream change, out of scope for an iOS-only plan. This is fine because, unlike free user-typed text, the reply's `body` is entirely client-constructed from a fixed template (see Wire Schema below) — the agent parses a known, deterministic format, not natural language, so no structured field is actually needed for reliable parsing.
- **Resolution state lives on the request event, updated via message edit — not client-side reply scanning.** The client has no existing mechanism to look up "what replies target this event" (unlike reactions, which the SDK aggregates onto their target automatically). Building one would be new, nontrivial infrastructure for a narrow use case. Instead, once the agent has processed an answer, it edits its own `io.element.agent.choice_request` message (message editing is already supported today, and this pattern is already anticipated by scenario #3, "pinned live task summary," in the original catalog) to add a `resolvedSelection` field. The client's rendering rule is entirely local to the one event it's already displaying: `resolvedSelection` absent → render tappable buttons; present → render static "Selected: X" text. No cross-event queries anywhere in the client.
- **Multi-select needs an explicit submit step; single-select does not.** For single-select, tapping a button sends the reply immediately — there's only ever one meaningful state. For multi-select, a first tap can't unambiguously mean "replace" or "add to" a prior tap, so multi-select buttons only toggle local, unsent UI state; a separate "Confirm" button (disabled until at least one option is toggled on) sends the actual reply event.

## Wire Schema

**Request** (`io.element.agent.choice_request`, posted by the agent):

```json
{
  "msgtype": "io.element.agent.choice_request",
  "body": "Which environment should this deploy to?\n\n• Test\n• Staging\n• Production",
  "question": "Which environment should this deploy to?",
  "options": [
    {"id": "test", "label": "Test"},
    {"id": "staging", "label": "Staging"},
    {"id": "prod", "label": "Production"}
  ],
  "multiSelect": false
}
```

`body` is always the required, human-readable fallback (question plus a plain-text listing of options) for clients that don't understand the msgtype — same role `body` plays in `io.element.agent.turn`. `resolvedSelection` is absent from the initial request entirely; it only appears, as an array of chosen option `id`s, in the edited version of this event once the agent has processed an answer.

**Response** (plain `m.text`, sent by whichever room member answers):

```json
{
  "msgtype": "m.text",
  "body": "Selected:\n• Staging",
  "m.relates_to": {"m.in_reply_to": {"event_id": "$original_request_event_id"}}
}
```

For multi-select, the same fixed format lists every chosen label, one bullet per line: `"Selected:\n• Staging\n• Production"`. No new client-side rendering is needed for this event at all — it's a standard text reply, indistinguishable from one a human typed by hand except for its fixed shape. The agent backend parses this deterministically: it already knows the `event_id` being replied to (via `m.relates_to.m.in_reply_to`) and the exact option labels it itself sent in that request, so matching each bulleted line back to a known label is exact-string matching, not NLP — reliable as long as the agent avoids duplicate/overlapping labels within one request, which is an authoring constraint on the agent side, not something the client needs to guard against.

## Components

Following the exact shape `io.element.agent.turn` established (`docs/superpowers/plans/2026-07-02-agent-turn-message-type.md`):

- **`AgentChoiceRequestRoomTimelineItemContent`** — model struct parsing `question`/`options`/`multiSelect`/`resolvedSelection` from the event's `originalJSON` (the Rust SDK only exposes `body` for an unrecognized `msgtype` via `MessageType.other`, so the structured fields must be recovered by hand, same reasoning `AgentTurnRoomTimelineItemContent` already documents for `tool_calls`).
- **`AgentChoiceRequestRoomTimelineItem`** — timeline item struct wrapping the content, registered the same way `AgentTurnRoomTimelineItem` was: a new `EventBasedMessageTimelineItemContentType` case, a new `RoomTimelineItemViewState` case, `RoomTimelineItemFactory` interception of the new msgtype string, and a mock fixture for previews/tests.
- **`AgentChoiceRequestRoomTimelineView`** — the SwiftUI card, wrapped in `TimelineStyler` (not `CollapsibleRoomTimelineView`'s pattern — that mistake was made and corrected once already in the `io.element.agent.turn` work, this plan should start from the corrected reference). Renders the question text, then either: a tappable button per option (single-select, immediate send) or a toggleable button row plus a "Confirm" button (multi-select, deferred send) or — if `resolvedSelection` is present — static "Selected: X" text with no buttons at all.

## Data Flow

1. Agent posts an `io.element.agent.choice_request` event.
2. Client renders the card via `AgentChoiceRequestRoomTimelineView`; every room member sees the same tappable buttons (no per-user targeting).
3. A room member taps (single-select) or toggles-then-confirms (multi-select); the client sends a plain `m.text` reply event whose `body` is the fixed "Selected:\n• Label" (or one bullet per chosen label for multi-select) template — no extra JSON field.
4. The agent backend reads the reply, decides how to act on it (including what to do about multiple different replies, if that happens — entirely the agent's business logic, not the client's).
5. The agent edits its original `io.element.agent.choice_request` event, setting `resolvedSelection`.
6. The client re-renders that same timeline item (same mechanism `io.element.agent.turn`/any edited message already uses) — buttons are replaced by the static "Selected: X" text.

## Error Handling

- **Malformed/unparseable `options`** (missing, empty, or fails to parse): render using only `body` as plain text, no buttons — the same graceful-degradation posture `io.element.agent.turn` takes toward malformed `tool_calls` entries.
- **Reply send failure** (offline, etc.): reuses the timeline's existing pending/failed message-send UX — no new error handling needed, since the reply is a normal `m.text` event going through the normal send pipeline.
- **Old/non-Element clients**: see the `body` fallback text for the request (a readable question + option list) and a completely normal-looking reply for the response — both degrade gracefully with zero special-casing needed on the sending side.

## Explicitly Out of Scope

- Free-text input fields (only closed-set choices are supported).
- Per-user targeting/authorization of who may answer.
- Any canvas UI — this is a Tier-1-equivalent, timeline-only feature despite being catalogued under Tier 2 in the original scenario list.
- Client-side aggregation or display of multiple simultaneous answers from different room members (the agent's edit is the only source of "resolved" truth the client renders).

## Testing

Same shape as `io.element.agent.turn`'s test coverage: unit tests for `AgentChoiceRequestRoomTimelineItemContent`'s JSON parsing (well-formed, missing options, malformed options, single vs. multi-select, `resolvedSelection` present/absent), and `TestablePreview`-driven snapshot/accessibility tests for `AgentChoiceRequestRoomTimelineView` covering at minimum: single-select unanswered, multi-select unanswered (some options toggled, Confirm enabled/disabled states), and resolved/answered state.
