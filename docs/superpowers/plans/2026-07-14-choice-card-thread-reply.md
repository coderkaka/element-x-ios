# Choice Card Thread Reply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a choice card response in its existing thread while still replying directly to the choice request event.

**Architecture:** Carry the current timeline's optional thread root with the choice action. Separate the thread root from the reply target in the room proxy raw event builder, preserving the existing non-thread fallback.

**Tech Stack:** Swift 6.2, SwiftUI Observation, Matrix room events, Swift Testing, Sourcery mocks.

## Global Constraints

- `m.relates_to.event_id` identifies the thread root.
- `m.relates_to.m.in_reply_to.event_id` identifies the choice request event.
- Existing error logging and threads-disabled behavior remain unchanged.
- Remove only the unavailable `caveman` requirement from `AGENTS.md`.

---

### Task 1: Remove stale repository guidance

**Files:**
- Modify: `AGENTS.md:4`

**Interfaces:**
- Consumes: User authorization to remove the unavailable skill rule.
- Produces: Repository instructions without the impossible edit gate.

- [ ] **Step 1: Remove the caveman clauses**

Change the opening guidance to retain the terse-voice requirement without naming an unavailable skill.

- [ ] **Step 2: Verify the stale reference is gone**

Run: `rg -n -i "caveman" AGENTS.md .agents .codex`

Expected: no matches.

### Task 2: Reproduce the nested-thread bug

**Files:**
- Modify: `UnitTests/Sources/TimelineViewModelTests.swift`

**Interfaces:**
- Consumes: `TimelineViewChoiceRequestAction.sendResponse(requestEventID:body:)` and `JoinedRoomProxyMock.sendThreadReply...Closure`.
- Produces: Tests requiring distinct `threadRootEventID` and `replyToEventID` values.

- [ ] **Step 1: Add failing tests**

Add tests that enable threads, create `.live` and `.thread(rootEventID:)` timeline controllers, send a choice response action, and assert the room proxy receives:

```swift
(body: "Selected", threadRootEventID: "choice", replyToEventID: "choice")
(body: "Selected", threadRootEventID: "root", replyToEventID: "choice")
```

- [ ] **Step 2: Run the targeted tests and verify RED**

Run: `swift run tools ci unit-tests --test-filter TimelineViewModelTests`

Expected: compile failure because the action and proxy do not yet accept separate thread-root and reply-target IDs.

### Task 3: Carry and encode the correct relations

**Files:**
- Modify: `ElementX/Sources/Screens/Timeline/TimelineModels.swift:46-48`
- Modify: `ElementX/Sources/Screens/Timeline/View/TimelineItemViews/AgentChoiceRequestRoomTimelineView.swift:153-159`
- Modify: `ElementX/Sources/Screens/Timeline/TimelineViewModel.swift:438-442`
- Modify: `ElementX/Sources/Screens/Timeline/TimelineInteractionHandler.swift:264-286`
- Modify: `ElementX/Sources/Services/Room/RoomProxyProtocol.swift:149-155`
- Modify: `ElementX/Sources/Services/Room/JoinedRoomProxy.swift:485-504`
- Modify: `ElementX/Sources/Mocks/Generated/GeneratedMocks.swift`

**Interfaces:**
- Produces: `sendResponse(requestEventID:threadRootEventID:body:)` and `sendThreadReply(body:threadRootEventID:replyToEventID:)`.

- [ ] **Step 1: Implement the minimal data flow**

Use `context.viewState.timelineKind.threadRootEventID` in the card view. In the interaction handler choose `existingThreadRootEventID ?? requestEventID`, then call:

```swift
roomProxy.sendThreadReply(body: body,
                          threadRootEventID: threadRootEventID ?? requestEventID,
                          replyToEventID: requestEventID)
```

Build raw relation content with the thread root in `event_id` and the choice request in `m.in_reply_to.event_id`.

- [ ] **Step 2: Regenerate Sourcery mocks**

Run: `sourcery --config Tools/Sourcery/AutoMockableConfig.yml`

Expected: `JoinedRoomProxyMock` exposes the new three-argument method.

- [ ] **Step 3: Run targeted tests and verify GREEN**

Run: `swift run tools ci unit-tests --test-filter TimelineViewModelTests`

Expected: new choice response tests pass.

### Task 4: Verify behavior and concurrency

**Files:**
- Review: all files modified above.

**Interfaces:**
- Consumes: Completed implementation and generated mocks.
- Produces: Build and static evidence that the fix is safe.

- [ ] **Step 1: Run formatting and diff checks**

Run: `swiftformat --lint .` and `git diff --check`.

Expected: no new formatting violations or whitespace errors.

- [ ] **Step 2: Build the app**

Run the ElementX simulator build with Xcode tooling.

Expected: build succeeds.

- [ ] **Step 3: Review Task usage**

Confirm the existing `Task` inherits MainActor isolation, captures no newly unsafe values, and introduces no detached work or unchecked sendability.

- [ ] **Step 4: Commit the fix**

Stage only `AGENTS.md`, the implementation files, generated mock, tests, and this plan. Commit with a descriptive title and body.
