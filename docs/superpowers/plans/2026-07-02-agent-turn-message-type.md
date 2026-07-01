# Agent-Turn Message Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new custom Matrix message type (`io.element.agent.turn`) that renders an AI agent's reply as a dedicated timeline item — final text plus an optional collapsible list of tool calls — instead of falling back to plain/unsupported text.

**Architecture:** Follows the exact pattern the timeline already uses for every other message type (text, location, poll, ...): a `RoomTimelineItemFactory` switch dispatches on `MessageType`, builds a concrete `RoomTimelineItemProtocol`-conforming struct wrapping a `Hashable` content struct, `RoomTimelineItemViewState` adds a case for it, and `RoomTimelineItemView` routes that case to a dedicated SwiftUI view. The only new mechanic: `io.element.agent.turn` arrives from the Rust SDK as `MessageType.other(msgtype:body:)` (any `m.room.message` with a msgtype the SDK doesn't recognize natively), which today is silently dropped (`return nil`); this plan intercepts that one specific msgtype instead of dropping it.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing (`@Test`/`#expect`/`#require`), MatrixRustSDK bindings, Sourcery-generated preview/accessibility tests, SwiftLint/SwiftFormat.

## Global Constraints

- Swift API naming: `ID` not `Id`, `URL` not `Url` (per AGENTS.md) — not directly relevant here but keep in mind for any future field names.
- No comments restating what the code already says; only comment non-obvious traps/justifications (AGENTS.md "Comments").
- All new/changed strings must go through `L10n` — this plan introduces no new user-facing strings that need translation (tool-call status labels are rendered from data, not localized copy), so `Untranslated.strings` is untouched. If a reviewer decides to add static labels later (e.g. "Tool calls"), add the key to `Untranslated.strings`, not `Localizable.strings`.
- Every new `RoomTimelineItemType`/`EventBasedMessageTimelineItemContentType` case must be added to *every* exhaustive switch over that type — Task 2 and Task 3 enumerate every call site found by grepping the whole codebase for `.location(` and `EventBasedMessageTimelineItemContentType` usages; do not assume the list is only "the obvious ones."
- `nonisolated` on new structs/enums, matching every sibling type in `Services/Timeline/TimelineItems/` (project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so service-layer types opt out explicitly).

## Assumptions to verify first (do this before Task 1)

Two facts about the Rust SDK bindings could not be confirmed from source (the xcframework is a binary dependency; no local source checkout was available). Both are addressed as literal first steps below, not left as silent guesses:

1. **`MessageType.other` associated value labels.** All evidence found (`RoomTimelineItemFactory.swift:922`: `case .other(_, let body):`) confirms it takes exactly two associated values, msgtype-then-body, matched positionally. Task 1's Step 1 constructs one with explicit labels (`msgtype:`, `body:`) — if the real labels differ, the compiler error names the correct ones; fix and continue.
2. **Whether `EventTimelineItemProxy.debugInfo.originalJSON` contains the full raw event (including `content.tool_calls`) or just the event's `content`.** Strong circumstantial evidence points to "full event": `TimelineItemDebugView.swift`'s preview shows the sibling `model` field as a full event dump (`event_id`, `sender`, `timestamp`, `content: Message(...)` all nested), and this is the same "View Source" mechanism every Matrix client uses to show the complete original event, not just its content. Task 4's parser handles **both** shapes defensively (tries full-event envelope first, falls back to content-only) specifically because this could not be verified against a live event in this environment (no working simulator/package-resolution setup was available at plan-writing time). When you run Task 4's test for the first time, if it fails, print the raw `originalJSON` from the test's mock and read AGENTS.md/re-check against a real device — the fix is a one-line change to which envelope shape wins, not a redesign.

## Task 1: `AgentTurnRoomTimelineItemContent` model + JSON parsing

**Files:**
- Create: `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentTurnRoomTimelineItemContent.swift`
- Test: `UnitTests/Sources/AgentTurnRoomTimelineItemContentTests.swift`

**Interfaces:**
- Produces: `AgentTurnRoomTimelineItemContent` (`Hashable`, `body: String`, `toolCalls: [ToolCallSummary]`), `ToolCallSummary` (`Hashable`, `name: String`, `status: ToolCallSummary.Status`, `summary: String`), `ToolCallSummary.Status` (`Hashable`, cases `.pending`, `.done`, `.failed`, `.other(String)`), static `AgentTurnRoomTimelineItemContent.msgType == "io.element.agent.turn"`, and `init(body:parsingToolCallsFrom:)` where the second parameter is the raw `originalJSON` string (or `nil`).

- [ ] **Step 1: Write the failing tests**

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

struct AgentTurnRoomTimelineItemContentTests {
    @Test
    func bodyOnlyNoOriginalJSON() {
        let content = AgentTurnRoomTimelineItemContent(body: "Final reply", parsingToolCallsFrom: nil)
        #expect(content.body == "Final reply")
        #expect(content.toolCalls == [])
    }

    @Test
    func parsesToolCallsFromFullEventEnvelope() {
        let originalJSON = """
        {
            "type": "m.room.message",
            "sender": "@agent:example.com",
            "content": {
                "msgtype": "io.element.agent.turn",
                "body": "Final reply",
                "tool_calls": [
                    {"name": "read_file", "status": "done", "summary": "Read Foo.swift"},
                    {"name": "search", "status": "pending", "summary": "Searching..."}
                ]
            }
        }
        """

        let content = AgentTurnRoomTimelineItemContent(body: "Final reply", parsingToolCallsFrom: originalJSON)

        #expect(content.toolCalls == [
            ToolCallSummary(name: "read_file", status: .done, summary: "Read Foo.swift"),
            ToolCallSummary(name: "search", status: .pending, summary: "Searching...")
        ])
    }

    @Test
    func parsesToolCallsFromContentOnlyEnvelope() {
        let originalJSON = """
        {
            "msgtype": "io.element.agent.turn",
            "body": "Final reply",
            "tool_calls": [
                {"name": "read_file", "status": "failed", "summary": "Could not read Foo.swift"}
            ]
        }
        """

        let content = AgentTurnRoomTimelineItemContent(body: "Final reply", parsingToolCallsFrom: originalJSON)

        #expect(content.toolCalls == [
            ToolCallSummary(name: "read_file", status: .failed, summary: "Could not read Foo.swift")
        ])
    }

    @Test
    func unrecognisedStatusFallsBackToOther() {
        let originalJSON = """
        {"content": {"tool_calls": [{"name": "read_file", "status": "queued", "summary": "..."}]}}
        """

        let content = AgentTurnRoomTimelineItemContent(body: "x", parsingToolCallsFrom: originalJSON)

        #expect(content.toolCalls == [ToolCallSummary(name: "read_file", status: .other("queued"), summary: "...")])
    }

    @Test
    func malformedJSONFallsBackToNoToolCalls() {
        let content = AgentTurnRoomTimelineItemContent(body: "x", parsingToolCallsFrom: "not json")
        #expect(content.toolCalls == [])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AgentTurnRoomTimelineItemContentTests` (or, once Xcode access is working, `xcodebuild test -scheme ElementX -only-testing:UnitTests/AgentTurnRoomTimelineItemContentTests`)
Expected: FAIL — `AgentTurnRoomTimelineItemContent` and `ToolCallSummary` don't exist yet (compile error).

- [ ] **Step 3: Write the implementation**

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct ToolCallSummary: Hashable {
    enum Status: Hashable {
        case pending
        case done
        case failed
        /// Any status value the client doesn't recognise yet — kept instead of dropped so a future
        /// agent backend can introduce new statuses without this client silently losing data.
        case other(String)
    }

    let name: String
    let status: Status
    let summary: String
}

extension ToolCallSummary: Decodable {}

extension ToolCallSummary.Status: Decodable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "pending": self = .pending
        case "done": self = .done
        case "failed": self = .failed
        default: self = .other(raw)
        }
    }
}

nonisolated struct AgentTurnRoomTimelineItemContent: Hashable {
    /// The custom `m.room.message` msgtype this content type is built from.
    static let msgType = "io.element.agent.turn"

    let body: String
    let toolCalls: [ToolCallSummary]

    init(body: String, toolCalls: [ToolCallSummary] = []) {
        self.body = body
        self.toolCalls = toolCalls
    }

    /// - Parameter originalJSON: the raw Matrix event JSON from `EventTimelineItemProxy.debugInfo.originalJSON`.
    ///   The Rust SDK only exposes the standard `body` field for custom msgtypes via `MessageType.other`,
    ///   so `tool_calls` has to be recovered by hand from the raw event. Tries a full-event envelope
    ///   (`{"content": {"tool_calls": [...]}}`) first, then a bare content object (`{"tool_calls": [...]}`),
    ///   because which shape `originalJSON` actually is wasn't confirmed against a live event when this
    ///   was written (see the plan's "Assumptions to verify first" section).
    init(body: String, parsingToolCallsFrom originalJSON: String?) {
        self.body = body
        toolCalls = Self.parseToolCalls(from: originalJSON)
    }

    private static func parseToolCalls(from originalJSON: String?) -> [ToolCallSummary] {
        guard let data = originalJSON?.data(using: .utf8) else { return [] }

        struct ContentEnvelope: Decodable {
            let toolCalls: [ToolCallSummary]

            enum CodingKeys: String, CodingKey {
                case toolCalls = "tool_calls"
            }
        }

        struct EventEnvelope: Decodable {
            let content: ContentEnvelope
        }

        let decoder = JSONDecoder()

        if let event = try? decoder.decode(EventEnvelope.self, from: data) {
            return event.content.toolCalls
        }

        if let content = try? decoder.decode(ContentEnvelope.self, from: data) {
            return content.toolCalls
        }

        return []
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AgentTurnRoomTimelineItemContentTests`
Expected: PASS, all 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentTurnRoomTimelineItemContent.swift UnitTests/Sources/AgentTurnRoomTimelineItemContentTests.swift
git commit -m "Add AgentTurnRoomTimelineItemContent model with tool-call JSON parsing"
```

## Task 2: `AgentTurnRoomTimelineItem` + register in `EventBasedMessageTimelineItemContentType`

**Files:**
- Create: `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentTurnRoomTimelineItem.swift`
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/EventBasedMessageTimelineItemProtocol.swift`

**Interfaces:**
- Consumes: `AgentTurnRoomTimelineItemContent` (Task 1).
- Produces: `AgentTurnRoomTimelineItem` (`EventBasedMessageTimelineItemProtocol`, `Equatable`, same stored-property shape as every sibling item: `id`, `timestamp`, `isOutgoing`, `isEditable`, `canBeRepliedTo`, `sender`, `content`, `properties`), `EventBasedMessageTimelineItemContentType.agentTurn(AgentTurnRoomTimelineItemContent)` case.

- [ ] **Step 1: Write the failing test**

```swift
// Add to UnitTests/Sources/AgentTurnRoomTimelineItemContentTests.swift (new @Test in the same struct)

    @Test
    func itemExposesBodyAndContentType() {
        let item = AgentTurnRoomTimelineItem(id: .randomEvent,
                                             timestamp: .mock,
                                             isOutgoing: false,
                                             isEditable: false,
                                             canBeRepliedTo: true,
                                             sender: .init(id: "@agent:example.com"),
                                             content: .init(body: "Final reply", toolCalls: []))

        #expect(item.body == "Final reply")
        #expect(item.contentType == .agentTurn(.init(body: "Final reply", toolCalls: [])))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter AgentTurnRoomTimelineItemContentTests`
Expected: FAIL — `AgentTurnRoomTimelineItem` doesn't exist and `EventBasedMessageTimelineItemContentType` has no `.agentTurn` case (compile error).

- [ ] **Step 3: Add the enum case and fix every exhaustive switch over it**

In `ElementX/Sources/Services/Timeline/TimelineItems/EventBasedMessageTimelineItemProtocol.swift`, change:

```swift
nonisolated enum EventBasedMessageTimelineItemContentType: Hashable {
    case audio(AudioRoomTimelineItemContent)
    case emote(EmoteRoomTimelineItemContent)
    case file(FileRoomTimelineItemContent)
    case image(ImageRoomTimelineItemContent)
    case notice(NoticeRoomTimelineItemContent)
    case text(TextRoomTimelineItemContent)
    case video(VideoRoomTimelineItemContent)
    case location(LocationRoomTimelineItemContent)
    case voice(AudioRoomTimelineItemContent)
    case agentTurn(AgentTurnRoomTimelineItemContent)
}
```

and update all three exhaustive switches in the same file (`supportsMediaCaption`, `mediaCaption`, `formattedMediaCaption`) by adding `.agentTurn` to the existing "no caption" case group, e.g.:

```swift
    var supportsMediaCaption: Bool {
        switch contentType {
        case .audio, .file, .image, .video:
            true
        case .emote, .notice, .text, .location, .voice, .agentTurn:
            false
        }
    }
```

(same edit — append `, .agentTurn` — to the matching case line in `mediaCaption` and `formattedMediaCaption`, which both already return `nil` for that group).

- [ ] **Step 4: Create the item struct**

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct AgentTurnRoomTimelineItem: EventBasedMessageTimelineItemProtocol, Equatable {
    let id: TimelineItemIdentifier
    let timestamp: Date
    let isOutgoing: Bool
    let isEditable: Bool
    let canBeRepliedTo: Bool

    let sender: TimelineItemSender

    let content: AgentTurnRoomTimelineItemContent

    var properties = RoomTimelineItemProperties()

    var body: String {
        content.body
    }

    var contentType: EventBasedMessageTimelineItemContentType {
        .agentTurn(content)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter AgentTurnRoomTimelineItemContentTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentTurnRoomTimelineItem.swift ElementX/Sources/Services/Timeline/TimelineItems/EventBasedMessageTimelineItemProtocol.swift UnitTests/Sources/AgentTurnRoomTimelineItemContentTests.swift
git commit -m "Add AgentTurnRoomTimelineItem and register it as a message content type"
```

## Task 3: Register in `RoomTimelineItemViewState`

**Files:**
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemViewState.swift`

**Interfaces:**
- Consumes: `AgentTurnRoomTimelineItem` (Task 2).
- Produces: `RoomTimelineItemType.agentTurn(AgentTurnRoomTimelineItem)` case, wired into every switch over `RoomTimelineItemType` in this file.

This file has four places that must all be updated — three are compiler-enforced (exhaustive switches will fail to build if you miss one), one (`init(item:)`) is not enforced (it has a `default: fatalError`) so it's easy to silently miss and only discover at runtime.

- [ ] **Step 1: Add the case to the enum**

In `RoomTimelineItemViewState.swift`, add to `RoomTimelineItemType` (after `.location`):

```swift
    case location(LocationRoomTimelineItem)
    case agentTurn(AgentTurnRoomTimelineItem)
    case poll(PollRoomTimelineItem)
```

- [ ] **Step 2: Add the runtime-dispatch case in `init(item:)`**

Find the `init(item: RoomTimelineItemProtocol)` switch (the one ending in `default: fatalError("Unknown timeline item")`) and add, after the `LocationRoomTimelineItem` case:

```swift
        case let item as LocationRoomTimelineItem:
            self = .location(item)
        case let item as AgentTurnRoomTimelineItem:
            self = .agentTurn(item)
        case let item as PollRoomTimelineItem:
            self = .poll(item)
```

- [ ] **Step 3: Add to the `id` switch**

Find the `var id: TimelineItemIdentifier` switch (the one that pattern-matches every case as `RoomTimelineItemProtocol` in one big comma-separated list ending `return item.id`) and add `.agentTurn(let item as RoomTimelineItemProtocol),` to the list, next to `.location(let item as RoomTimelineItemProtocol),`.

- [ ] **Step 4: Add to the `timestamp` switch**

Find `var timestamp: Date?` and add, after the `.location` case:

```swift
        case .location(let item):
            return item.timestamp
        case .agentTurn(let item):
            return item.timestamp
        case .poll(let item):
            return item.timestamp
```

- [ ] **Step 5: Build to confirm exhaustiveness**

Run: `swift build` (or `xcodebuild build -scheme ElementX` once Xcode access is working)
Expected: builds cleanly — if any switch was missed, the compiler reports "switch must be exhaustive" at that exact location.

- [ ] **Step 6: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemViewState.swift
git commit -m "Register AgentTurnRoomTimelineItem as a RoomTimelineItemType case"
```

## Task 4: Factory — intercept `io.element.agent.turn` and build the item

**Files:**
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemFactory.swift`
- Modify: `ElementX/Sources/Mocks/SDK/EventTimelineItem.swift`
- Test: `UnitTests/Sources/TimelineItemFactoryTests.swift`

**Interfaces:**
- Consumes: `AgentTurnRoomTimelineItem`/`AgentTurnRoomTimelineItemContent` (Tasks 1–2), `EventTimelineItemProxy.debugInfo.originalJSON` (existing, `TimelineItemProxy.swift:139-142`).
- Produces: `EventTimelineItem.mockAgentTurn(toolCallsJSON:)` static mock factory for tests.

- [ ] **Step 1: Remove the throwaway spike test, if still present**

If `UnitTests/Sources/TimelineItemFactoryTests.swift` still has the `spikeOtherMsgTypeLabels()` test from the plan-writing spike, delete that whole `@Test func spikeOtherMsgTypeLabels()` block now — it's superseded by Step 2 below.

- [ ] **Step 2: Add the mock fixture**

In `ElementX/Sources/Mocks/SDK/EventTimelineItem.swift`, add this to the `EventTimelineItem` extension (after `mockCallInvite`):

```swift
    static func mockAgentTurn(body: String = "Final reply", originalJSON: String? = nil) -> EventTimelineItem {
        let messageType = MessageType.other(msgtype: AgentTurnRoomTimelineItemContent.msgType, body: body)

        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))

        var configuration = EventTimelineItemSDKMockConfiguration(content: content)
        // EventTimelineItemSDKMockConfiguration doesn't expose originalJSON directly (it's set on the
        // lazyProvider inside EventTimelineItem's own init), so build the item then patch debugInfo after.
        let item = EventTimelineItem(configuration: configuration)
        _ = configuration // keep the local binding intentional (see note below if the compiler warns unused)
        return item
    }
```

Note before writing this for real: `EventTimelineItemSDKMockConfiguration` (seen in full at `ElementX/Sources/Mocks/SDK/EventTimelineItem.swift:14-28`) has **no** `originalJSON` field — `debugInfoReturnValue` is hardcoded to `.init(model: "", originalJson: nil, latestEditJson: nil)` inside `EventTimelineItem.init(configuration:)` (line 35) and there is no way to override it from outside that init today. Since Task 4 needs a mock event whose `debugInfo.originalJSON` returns a specific string, **this step must first add an `originalJSON: String?` field to `EventTimelineItemSDKMockConfiguration`** and thread it through to `lazyProvider.debugInfoReturnValue`. Do that first:

```swift
// In EventTimelineItemSDKMockConfiguration (ElementX/Sources/Mocks/SDK/EventTimelineItem.swift:14-28), add:
    var originalJSON: String?

// In EventTimelineItem.init(configuration:) (same file, ~line 35), change:
    lazyProvider.debugInfoReturnValue = .init(model: "", originalJson: configuration.originalJSON, latestEditJson: nil)
```

Then `mockAgentTurn` becomes:

```swift
    static func mockAgentTurn(body: String = "Final reply", originalJSON: String? = nil) -> EventTimelineItem {
        let messageType = MessageType.other(msgtype: AgentTurnRoomTimelineItemContent.msgType, body: body)

        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))

        return .init(configuration: .init(content: content, originalJSON: originalJSON))
    }
```

(`EventTimelineItemSDKMockConfiguration`'s memberwise-style calls elsewhere, e.g. `.init(sender: sender, content: .callInvite)` in `mockCallInvite`, keep compiling unchanged since `originalJSON` defaults to `nil`.)

- [ ] **Step 3: Write the failing factory test**

Add to `UnitTests/Sources/TimelineItemFactoryTests.swift`:

```swift
    @Test
    func agentTurnWithToolCalls() throws {
        let ownUserID = "@alice:matrix.org"
        let senderUserID = "@agent:matrix.org"

        let factory = RoomTimelineItemFactory(userID: ownUserID,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: ownUserID))

        let originalJSON = """
        {"content": {"tool_calls": [{"name": "read_file", "status": "done", "summary": "Read Foo.swift"}]}}
        """

        let eventTimelineItem = EventTimelineItem.mockAgentTurn(body: "Done reading.", originalJSON: originalJSON)
        let eventTimelineItemProxy = EventTimelineItemProxy(item: eventTimelineItem, uniqueID: .init("0"))

        let item = try #require(factory.buildTimelineItem(for: eventTimelineItemProxy, isDM: false) as? AgentTurnRoomTimelineItem,
                                "Incorrect item type")

        #expect(item.content.body == "Done reading.")
        #expect(item.content.toolCalls == [ToolCallSummary(name: "read_file", status: .done, summary: "Read Foo.swift")])
        #expect(item.sender == TimelineItemSender(id: senderUserID))
    }

    @Test
    func unrecognisedCustomMsgtypeIsStillDropped() throws {
        let ownUserID = "@alice:matrix.org"

        let factory = RoomTimelineItemFactory(userID: ownUserID,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: ownUserID))

        let messageType = MessageType.other(msgtype: "some.other.custom.type", body: "unhandled")
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: "unhandled",
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        let eventTimelineItem = EventTimelineItem(configuration: .init(content: content))
        let eventTimelineItemProxy = EventTimelineItemProxy(item: eventTimelineItem, uniqueID: .init("0"))

        #expect(factory.buildTimelineItem(for: eventTimelineItemProxy, isDM: false) == nil)
    }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `swift test --filter TimelineItemFactoryTests`
Expected: FAIL — `mockAgentTurn` doesn't exist yet / factory still returns `nil` for `io.element.agent.turn` (whichever compiles first will fail first; both must eventually pass).

- [ ] **Step 5: Update the factory**

In `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemFactory.swift`, change the `buildMessageTimelineItem` switch (currently ending `case .other: return nil`):

```swift
        case .gallery(let galleryMessageContent):
            return buildGalleryTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, galleryMessageContent, isOutgoing)
        case .other(let msgtype, let body):
            guard msgtype == AgentTurnRoomTimelineItemContent.msgType else { return nil }
            return buildAgentTurnTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, body, isOutgoing)
        }
    }
```

and add a new private method next to `buildLocationTimelineItem` (same file), copying its shape exactly:

```swift
    private func buildAgentTurnTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                            _ messageLikeContent: MsgLikeContent,
                                            _ messageContent: MessageContent,
                                            _ body: String,
                                            _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        AgentTurnRoomTimelineItem(id: eventItemProxy.id,
                                 timestamp: eventItemProxy.timestamp,
                                 isOutgoing: isOutgoing,
                                 isEditable: eventItemProxy.isEditable,
                                 canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                 sender: eventItemProxy.sender,
                                 content: .init(body: body, parsingToolCallsFrom: eventItemProxy.debugInfo.originalJSON),
                                 properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                   isThreaded: messageLikeContent.threadRoot != nil,
                                                   threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                   isEdited: messageContent.isEdited,
                                                   reactions: buildAggregatedReactions(messageLikeContent.reactions),
                                                   deliveryStatus: eventItemProxy.deliveryStatus,
                                                   orderedReadReceipts: buildOrderedReadReceipts(eventItemProxy.readReceipts),
                                                   encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                   encryptionForwarder: eventItemProxy.forwarder))
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter TimelineItemFactoryTests`
Expected: PASS, including the pre-existing `callInvite` test (make sure nothing regressed).

- [ ] **Step 7: If `agentTurnWithToolCalls` fails on the tool-calls assertion specifically**

This means the "Assumptions to verify first" guess about which JSON envelope shape is wrong in a way the defensive double-decode in Task 1 doesn't already cover — print `eventItemProxy.debugInfo.originalJSON` in the test to see the actual mock value (it's whatever you passed to `mockAgentTurn(originalJSON:)`, so this only tells you the parser bug, not the real SDK's shape). To check the *real* SDK's shape, this needs a live app + live homeserver event (see plan header) — file that as a follow-up, don't block this task on it, since the mock test only proves the parser handles the shapes it's given correctly.

- [ ] **Step 8: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemFactory.swift ElementX/Sources/Mocks/SDK/EventTimelineItem.swift UnitTests/Sources/TimelineItemFactoryTests.swift
git commit -m "Build AgentTurnRoomTimelineItem from io.element.agent.turn messages"
```

## Task 5: SwiftUI view with collapsible tool calls

**Files:**
- Create: `ElementX/Sources/Screens/Timeline/View/TimelineItemViews/AgentTurnRoomTimelineView.swift`
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemView.swift`

**Interfaces:**
- Consumes: `AgentTurnRoomTimelineItem` (Task 2), Compound tokens (`Color.compound.*`, `Font.compound.*`, `CompoundIcon`), the collapsible-disclosure pattern from `CollapsibleRoomTimelineView.swift:12-72`.
- Produces: `AgentTurnRoomTimelineView: View`.

This task has no unit test of its own — correctness is covered by the Sourcery-generated snapshot + accessibility tests, which key off `PreviewProvider, TestablePreview` conformance (`Tools/Sourcery/PreviewTests.stencil:28-34`) and require no manual annotation.

- [ ] **Step 1: Create the view**

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct AgentTurnRoomTimelineView: View {
    let timelineItem: AgentTurnRoomTimelineItem

    @State private var isToolCallsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !timelineItem.content.toolCalls.isEmpty {
                toolCallsDisclosure
            }

            Text(timelineItem.content.body)
                .font(.compound.bodyMD)
                .foregroundColor(.compound.textPrimary)
        }
    }

    private var toolCallsDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withElementAnimation {
                    isToolCallsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(timelineItem.content.toolCalls.count) tool calls")
                        .font(.compound.bodySM)
                    CompoundIcon(\.chevronRight, size: .small, relativeTo: .compound.bodySM)
                        .rotationEffect(.degrees(isToolCallsExpanded ? 90 : 0))
                        .animation(.elementDefault, value: isToolCallsExpanded)
                }
                .foregroundColor(.compound.textSecondary)
            }
            .buttonStyle(.plain)

            if isToolCallsExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(timelineItem.content.toolCalls.enumerated()), id: \.offset) { _, toolCall in
                        toolCallRow(toolCall)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func toolCallRow(_ toolCall: ToolCallSummary) -> some View {
        HStack(spacing: 8) {
            statusIcon(for: toolCall.status)
            VStack(alignment: .leading, spacing: 0) {
                Text(toolCall.name)
                    .font(.compound.bodySMSemibold)
                Text(toolCall.summary)
                    .font(.compound.bodyXS)
                    .foregroundColor(.compound.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: ToolCallSummary.Status) -> some View {
        switch status {
        case .pending:
            CompoundIcon(\.time, size: .xSmall, relativeTo: .compound.bodyXS)
                .foregroundColor(.compound.iconSecondary)
        case .done:
            CompoundIcon(\.check, size: .xSmall, relativeTo: .compound.bodyXS)
                .foregroundColor(.compound.iconSuccessPrimary)
        case .failed:
            CompoundIcon(\.error, size: .xSmall, relativeTo: .compound.bodyXS)
                .foregroundColor(.compound.iconCriticalPrimary)
        case .other:
            CompoundIcon(\.info, size: .xSmall, relativeTo: .compound.bodyXS)
                .foregroundColor(.compound.iconSecondary)
        }
    }
}

struct AgentTurnRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        PreviewScrollView {
            VStack(spacing: 8) {
                states
            }
        }
        .previewLayout(.sizeThatFits)
    }

    @ViewBuilder
    static var states: some View {
        AgentTurnRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                       timestamp: .mock,
                                                       isOutgoing: false,
                                                       isEditable: false,
                                                       canBeRepliedTo: true,
                                                       sender: .init(id: "@agent:example.com"),
                                                       content: .init(body: "Final reply, no tool calls.")))

        AgentTurnRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                       timestamp: .mock,
                                                       isOutgoing: false,
                                                       isEditable: false,
                                                       canBeRepliedTo: true,
                                                       sender: .init(id: "@agent:example.com"),
                                                       content: .init(body: "Done reading and searching.",
                                                                      toolCalls: [
                                                                          ToolCallSummary(name: "read_file", status: .done, summary: "Read Foo.swift"),
                                                                          ToolCallSummary(name: "search", status: .pending, summary: "Searching for usages...")
                                                                      ])))
    }
}
```

Before finalizing this file, verify the icon key paths used (`\.time`, `\.check`, `\.error`, `\.info`, `\.chevronRight`) actually exist on `CompoundIcons` — grep `compound-ios/Sources/Compound/` for the closest matches and swap in whatever the design system actually names them; these four were picked by best guess from common Compound icon naming and were not individually confirmed against the icon catalogue.

- [ ] **Step 2: Wire it into the dispatch switch**

In `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemView.swift`, add (next to the `.location` case):

```swift
        case .location(let item):
            LocationRoomTimelineView(timelineItem: item)
        case .agentTurn(let item):
            AgentTurnRoomTimelineView(timelineItem: item)
        case .poll(let item):
            PollRoomTimelineView(timelineItem: item)
```

- [ ] **Step 3: Regenerate Sourcery-derived test files**

Run: `sourcery --config Tools/Sourcery/PreviewTestsConfig.yml`
Expected: `PreviewTests/Sources/GeneratedPreviewTests.swift` gains a new `agentTurnRoomTimelineView()` test function. Also run the `AccessibilityTests.yml` and `TestablePreviewsDictionary.yml` configs the same way (AGENTS.md lists all Sourcery configs under one `sourcery` command per config).

- [ ] **Step 4: Build and run the generated snapshot test**

Run: `xcodebuild test -scheme ElementX -only-testing:PreviewTests/GeneratedPreviewTests/agentTurnRoomTimelineView` (adjust test identifier to whatever Sourcery actually generated in Step 3)
Expected: PASS on first run (snapshot tests record a reference image the first time in this codebase's snapshot-testing setup — confirm against `swift-snapshot-testing`'s recording mode if it instead fails asking you to record).

- [ ] **Step 5: Commit**

```bash
git add ElementX/Sources/Screens/Timeline/View/TimelineItemViews/AgentTurnRoomTimelineView.swift ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemView.swift PreviewTests/Sources/GeneratedPreviewTests.swift AccessibilityTests/Sources/*.swift
git commit -m "Render agent-turn messages with a collapsible tool-calls section"
```

## Self-Review Notes

- **Spec coverage:** the design doc's decided scenario #1 (dedicated agent-turn message type, structured `tool_calls`) is fully covered — Tasks 1-2 build the model, Task 3 registers it with the view-state layer, Task 4 wires the factory (including the fallback-to-`nil` behavior for *other* unrecognized custom msgtypes, which stays unchanged — explicitly tested in Task 4's second test so nobody "fixes" that as a drive-by), Task 5 renders it.
- **Placeholder scan:** the two genuinely unverified facts (SDK label names, `originalJSON` shape) are called out explicitly with a concrete fallback/adjustment step each, not left as unmarked assumptions.
- **Type consistency:** `AgentTurnRoomTimelineItemContent`, `ToolCallSummary`, `ToolCallSummary.Status` are named identically across all five tasks; `AgentTurnRoomTimelineItem`'s stored properties match every sibling `*RoomTimelineItem` struct's shape exactly.
- **Known residual risk carried forward, not silently dropped:** whether `debugInfo.originalJSON` is a full-event or content-only envelope. Flagged in the plan header, in Task 1 (parser handles both), and in Task 4 Step 7 (what to do if the live shape turns out to differ). This is the single most likely thing to require a follow-up fix once run against a real agent backend.
