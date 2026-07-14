# Choice Card Thread Reply Design

## Problem

Choice responses currently use the choice request event ID as both the thread root and the reply target. This works for cards in the main timeline, but attempts to create a nested thread when the card is already inside a thread.

## Design

Carry an optional existing thread root through `TimelineViewChoiceRequestAction` into `TimelineInteractionHandler`.

When threads are enabled:

- A card in the main timeline starts a thread rooted at the choice request event.
- A card in a thread reuses that thread's root.
- `m.in_reply_to` always targets the choice request event so the agent can associate the response with the card.

`JoinedRoomProxy.sendThreadReply` will therefore accept separate thread-root and reply-to event IDs. When threads are disabled, the existing main-timeline reply path remains unchanged.

## Error Handling

Keep existing send-error logging. User-facing error behavior is outside this fix.

## Tests

- Verify raw content uses the choice request as both root and reply target for a main-timeline card.
- Verify raw content uses the existing root while replying to the choice request for a card inside a thread.
- Verify threads-disabled behavior continues through the normal timeline controller reply path.

## Repository Guidance

Remove the unavailable `caveman` skill requirement from `AGENTS.md`. Leave the remaining repository instructions unchanged.
