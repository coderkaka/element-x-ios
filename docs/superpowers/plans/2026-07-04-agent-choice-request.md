# Agent Choice Request Message Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `io.element.agent.choice_request` timeline message type rendering as a card with single/multi-select buttons, following the exact extensibility path already proven by `io.element.agent.turn`.

**Architecture:** New content model (`AgentChoiceRequestRoomTimelineItemContent`) parses `question`/`options`/`multi_select`/`resolved_selection` from the event's raw JSON (the Rust SDK only exposes `body` for unrecognized msgtypes). New timeline item (`AgentChoiceRequestRoomTimelineItem`) registers through the same four extension points `io.element.agent.turn` already went through: `EventBasedMessageTimelineItemContentType`, `RoomTimelineItemViewState`/`RoomTimelineItemType`, `RoomTimelineItemFactory`, and a dedicated SwiftUI card wrapped in `TimelineStyler`. The card sends its answer as a plain `m.text` reply via the existing `TimelineProxy.sendMessage(_:html:inReplyToEventID:intentionalMentions:)` API (no new send capability needed) and renders its "resolved" state by reading `resolved_selection` from whichever content is currently authoritative for its own event (the latest edit if one exists, otherwise the original).

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing (`@Test`/`#expect`), Compound (`ListRow`-free custom button row, `CompoundButtonStyle`), Sourcery-generated `TestablePreview` snapshot/accessibility tests.

## Global Constraints

- This Linux machine has no local Swift/Xcode toolchain — every build/test runs over SSH on a remote Mac (`ssh -i ~/.ssh/id_ed25519_kaka zhangqiong@mac-mini.tail2edbaa.ts.net "cd ~/Code/element-x-ios && <command>"`). Implement and commit locally on Linux, push to `coderkaka feature/space-tab-bar`, then SSH to the Mac to pull, build, and test.
- New files must be registered in `ElementX.xcodeproj/project.pbxproj` — run `/opt/homebrew/bin/xcodegen` on the Mac after pulling and verify via `grep -c '<NewFileName>' ElementX.xcodeproj/project.pbxproj` (nonzero). If `xcodegen` changes `project.pbxproj`, pull that change back to this Linux repo and commit it — do not leave it Mac-local-only. This has been a recurring gap across every prior task in this session; do not skip the verification step.
- New or changed `TestablePreview`/`PreviewProvider` types need Sourcery regeneration: `sourcery --config Tools/Sourcery/PreviewTestsConfig.yml && sourcery --config Tools/Sourcery/TestablePreviewsDictionary.yml && sourcery --config Tools/Sourcery/AccessibilityTests.yml` — commit the regenerated output, don't leave it Mac-local.
- `Untranslated.strings` entries generate into a separate `UntranslatedL10n` enum (`ElementX/Sources/Generated/Strings+Untranslated.swift`), not the main `L10n` enum (`Strings.swift`). Any new user-facing string in this plan must be added to `ElementX/Resources/Localizations/en.lproj/Untranslated.strings` and consumed as `UntranslatedL10n.*`, never `L10n.*`.
- Any change to `EventBasedMessageTimelineItemContentType` (a `nonisolated enum` in `EventBasedMessageTimelineItemProtocol.swift`) is exhaustively switched over in **six** places across the codebase, not just its own declaration file — verified for this plan by grepping the existing `.agentTurn` case, the closest precedent, before writing Task 2: `EventBasedMessageTimelineItemProtocol.swift` (3 switches: `supportsMediaCaption`, `mediaCaption`, `formattedMediaCaption`), `EventBasedTimelineItemProtocol.swift` (`isCopyable`), `TimelineReplyView.swift`, `TimelineThreadSummaryView.swift`, `RoomTimelineItemViewState.swift` (4 separate points: the `RoomTimelineItemType` case, its `init(item:)` dispatch, its `id` switch, its `timestamp` switch), and `RoomTimelineItemView.swift`'s view-dispatch switch. Task 2 covers the first four files (none of them reference the concrete SwiftUI view type, only the content), Task 3 covers `RoomTimelineItemViewState.swift`, and Task 5 covers `RoomTimelineItemView.swift` (which does reference the concrete view type, so it can only be wired once that view exists).
- The msgtype string is `io.element.agent.choice_request`, defined once as `AgentChoiceRequestRoomTimelineItemContent.msgType` and referenced everywhere else via that constant, never a duplicated string literal (matching `AgentTurnRoomTimelineItemContent.msgType`'s existing precedent).
- Wire field names are `snake_case` (`multi_select`, `resolved_selection`), matching the established convention already used for `tool_calls` in `io.element.agent.turn` — this differs from the illustrative camelCase JSON in the design doc (`docs/superpowers/specs/2026-07-04-agent-choice-request-design.md`), which was written before this codebase's actual snake_case convention was cross-checked against `AgentTurnRoomTimelineItemContent.swift`'s `CodingKeys`. Concrete field names, concrete types, and their exact meaning are unchanged from the spec — only the wire casing is corrected here.
- **Unverified assumption, must be confirmed empirically during Task 1:** whether `EventTimelineItemProxy.debugInfo.latestEditJSON` (see `TimelineItemProxy.swift:141,165`) contains the raw edit event's JSON (fields nested under an `m.new_content` key, per the Matrix spec's `m.replace` shape) or an SDK-pre-flattened equivalent of the replacement content (fields at the top level, same shape as `originalJSON`). This could not be determined from the vendored SDK bindings (`matrix_sdk_ffi.swift` declares the field with no documentation) or from any existing test fixture in this codebase (nothing currently parses `latestEditJSON` for content, only `TimelineItemDebugView.swift` displays it as raw text for debugging). Task 1's parser is written defensively to handle both shapes (see Step 3's `ContentEnvelope.init(from:)`), and Task 1's test suite covers both hypothesized shapes so the implementation isn't gated on resolving this uncertainty up front — but the implementer must verify against a **real edited event** sent through the actual test homeserver (`https://mac-mini.tail2edbaa.ts.net:8446`, already in use elsewhere this session) before reporting DONE, and note in their report which shape was observed in practice.

---

## Task 1: `AgentChoiceRequestRoomTimelineItemContent` model and JSON parsing

**Files:**
- Create: `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentChoiceRequestRoomTimelineItemContent.swift`
- Test: `UnitTests/Sources/AgentChoiceRequestRoomTimelineItemContentTests.swift`

**Interfaces:**
- Produces: `ChoiceOption: Hashable, Decodable` (`id: String`, `label: String`); `AgentChoiceRequestRoomTimelineItemContent: Hashable` (`static let msgType = "io.element.agent.choice_request"`; `body: String`; `question: String`; `options: [ChoiceOption]`; `multiSelect: Bool`; `resolvedSelection: [String]?`); `init(body:parsingFrom:latestEditJSON:)`.

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/Sources/AgentChoiceRequestRoomTimelineItemContentTests.swift`:

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Testing

@testable import ElementX

struct AgentChoiceRequestRoomTimelineItemContentTests {
    @Test
    func parsesWellFormedSingleSelectRequest() {
        let json = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"fallback",
        "question":"Which environment?","options":[{"id":"test","label":"Test"},{"id":"prod","label":"Production"}],
        "multi_select":false}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: json, latestEditJSON: nil)
        #expect(content.question == "Which environment?")
        #expect(content.options == [ChoiceOption(id: "test", label: "Test"), ChoiceOption(id: "prod", label: "Production")])
        #expect(content.multiSelect == false)
        #expect(content.resolvedSelection == nil)
    }
    
    @Test
    func parsesWellFormedMultiSelectRequest() {
        let json = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"fallback",
        "question":"Which reviewers?","options":[{"id":"a","label":"Alice"},{"id":"b","label":"Bob"}],
        "multi_select":true}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: json, latestEditJSON: nil)
        #expect(content.multiSelect == true)
    }
    
    @Test
    func missingOptionsFieldFallsBackToEmpty() {
        let json = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"fallback","question":"Q?","multi_select":false}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: json, latestEditJSON: nil)
        #expect(content.options.isEmpty)
        #expect(content.question == "Q?")
    }
    
    @Test
    func malformedOptionsEntryFallsBackToEmpty() {
        let json = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"fallback","question":"Q?",
        "options":[{"id":"a"}],"multi_select":false}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: json, latestEditJSON: nil)
        #expect(content.options.isEmpty)
    }
    
    @Test
    func nilOriginalJSONFallsBackToEmptyDefaults() {
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: nil, latestEditJSON: nil)
        #expect(content.question.isEmpty)
        #expect(content.options.isEmpty)
        #expect(content.multiSelect == false)
        #expect(content.resolvedSelection == nil)
    }
    
    @Test
    func uneditedMessageHasNoResolvedSelection() {
        let json = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"fallback","question":"Q?",
        "options":[{"id":"a","label":"A"}],"multi_select":false}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: json, latestEditJSON: nil)
        #expect(content.resolvedSelection == nil)
    }
    
    @Test
    func editedMessageWithNestedNewContentShapeExposesResolvedSelection() {
        // Hypothesis A: latestEditJSON is the raw m.replace edit event, replacement fields nested under `m.new_content`.
        let original = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"fallback","question":"Q?",
        "options":[{"id":"a","label":"A"}],"multi_select":false}}
        """
        let edit = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"* Selected: A",
        "m.new_content":{"msgtype":"io.element.agent.choice_request","body":"Selected: A","question":"Q?",
        "options":[{"id":"a","label":"A"}],"multi_select":false,"resolved_selection":["a"]},
        "m.relates_to":{"rel_type":"m.replace","event_id":"$original"}}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: original, latestEditJSON: edit)
        #expect(content.resolvedSelection == ["a"])
    }
    
    @Test
    func editedMessageWithFlatShapeExposesResolvedSelection() {
        // Hypothesis B: latestEditJSON is already the pre-flattened replacement content, same shape as originalJSON.
        let original = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"fallback","question":"Q?",
        "options":[{"id":"a","label":"A"}],"multi_select":false}}
        """
        let edit = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"Selected: A","question":"Q?",
        "options":[{"id":"a","label":"A"}],"multi_select":false,"resolved_selection":["a"]}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: original, latestEditJSON: edit)
        #expect(content.resolvedSelection == ["a"])
    }
    
    @Test
    func editedMessageMultiSelectResolvedSelectionHasMultipleIDs() {
        let edit = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"Selected: A, B","question":"Q?",
        "options":[{"id":"a","label":"A"},{"id":"b","label":"B"}],"multi_select":true,"resolved_selection":["a","b"]}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: nil, latestEditJSON: edit)
        #expect(content.resolvedSelection == ["a", "b"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run over SSH on the Mac: `xcodebuild test -project ElementX.xcodeproj -scheme UnitTests -destination 'platform=iOS Simulator,id=<current simulator id>' -only-testing:UnitTests/AgentChoiceRequestRoomTimelineItemContentTests`
Expected: FAIL (build error — `AgentChoiceRequestRoomTimelineItemContent` doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Create `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentChoiceRequestRoomTimelineItemContent.swift`:

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct ChoiceOption: Hashable, Decodable {
    let id: String
    let label: String
}

nonisolated struct AgentChoiceRequestRoomTimelineItemContent: Hashable {
    /// The custom `m.room.message` msgtype this content type is built from.
    static let msgType = "io.element.agent.choice_request"
    
    let body: String
    let question: String
    let options: [ChoiceOption]
    let multiSelect: Bool
    let resolvedSelection: [String]?
    
    init(body: String, question: String = "", options: [ChoiceOption] = [], multiSelect: Bool = false, resolvedSelection: [String]? = nil) {
        self.body = body
        self.question = question
        self.options = options
        self.multiSelect = multiSelect
        self.resolvedSelection = resolvedSelection
    }
    
    /// - Parameters:
    ///   - originalJSON: the raw Matrix event JSON from `EventTimelineItemProxy.debugInfo.originalJSON`.
    ///     The Rust SDK only exposes the standard `body` field for custom msgtypes via `MessageType.other`,
    ///     so `question`/`options`/`multi_select`/`resolved_selection` have to be recovered by hand from
    ///     the raw event — the same reasoning `AgentTurnRoomTimelineItemContent` documents for `tool_calls`.
    ///   - latestEditJSON: `EventTimelineItemProxy.debugInfo.latestEditJSON`, non-nil once the agent has
    ///     edited this message to resolve it. Whichever of the two is non-nil and parses successfully wins,
    ///     preferring the edit — this is how the client learns `resolved_selection` without any cross-event
    ///     reply-scanning, per this plan's design doc.
    init(body: String, parsingFrom originalJSON: String?, latestEditJSON: String?) {
        self.body = body
        let fields = Self.parseFields(from: latestEditJSON) ?? Self.parseFields(from: originalJSON)
        question = fields?.question ?? ""
        options = fields?.options ?? []
        multiSelect = fields?.multiSelect ?? false
        resolvedSelection = fields?.resolvedSelection
    }
    
    private struct Fields: Decodable {
        let question: String
        let options: [ChoiceOption]
        let multiSelect: Bool
        let resolvedSelection: [String]?
        
        enum CodingKeys: String, CodingKey {
            case question
            case options
            case multiSelect = "multi_select"
            case resolvedSelection = "resolved_selection"
        }
    }
    
    /// Matrix message edits (`m.replace`) nest their replacement content under `m.new_content`, while an
    /// unedited event's fields live directly under `content`. Whether `latestEditJSON` is the raw edit event
    /// (needing this unwrap) or already-flattened replacement content (not needing it) wasn't discoverable
    /// from the vendored SDK bindings — this handles both shapes without needing to know which is real.
    private struct ContentEnvelope: Decodable {
        let fields: Fields
        
        enum CodingKeys: String, CodingKey {
            case newContent = "m.new_content"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let newContent = try container.decodeIfPresent(Fields.self, forKey: .newContent) {
                fields = newContent
            } else {
                fields = try Fields(from: decoder)
            }
        }
    }
    
    private struct EventEnvelope: Decodable {
        let content: ContentEnvelope
    }
    
    private static func parseFields(from json: String?) -> Fields? {
        guard let data = json?.data(using: .utf8) else { return nil }
        guard let event = try? JSONDecoder().decode(EventEnvelope.self, from: data) else { return nil }
        return event.content.fields
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run over SSH on the Mac: `xcodebuild test -project ElementX.xcodeproj -scheme UnitTests -destination 'platform=iOS Simulator,id=<current simulator id>' -only-testing:UnitTests/AgentChoiceRequestRoomTimelineItemContentTests`
Expected: PASS, all 9 tests. Real console output required (e.g. `✔ Suite AgentChoiceRequestRoomTimelineItemContentTests passed after N seconds.`), not "should pass."

- [ ] **Step 5: Empirically verify the `latestEditJSON` shape against a real edit**

Using the test homeserver already available this session (`https://mac-mini.tail2edbaa.ts.net:8446`), send a message from one test account, then edit it from that same account (any normal text edit is enough — this is about observing the SDK's `debugInfo.latestEditJson` shape in general, not specifically an `io.element.agent.choice_request` message). View the message's "View Source"/debug info in the running app (`TimelineItemDebugView.swift` already surfaces `latestEditJSON` as a raw string) and note whether it contains a top-level `m.new_content` key or looks pre-flattened. Record this finding in your task report — it confirms (or corrects) the defensive parsing in Step 3, and tells the next task's reviewer whether the `ContentEnvelope` unwrap branch is the one actually exercised in production.

- [ ] **Step 6: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentChoiceRequestRoomTimelineItemContent.swift \
        UnitTests/Sources/AgentChoiceRequestRoomTimelineItemContentTests.swift
git commit -m "Add AgentChoiceRequestRoomTimelineItemContent with dual-shape edit parsing"
```

---

## Task 2: `AgentChoiceRequestRoomTimelineItem` and content-type registration

**Files:**
- Create: `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentChoiceRequestRoomTimelineItem.swift`
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/EventBasedMessageTimelineItemProtocol.swift`
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/EventBasedTimelineItemProtocol.swift:105-110` (add `.choiceRequest` to the `isCopyable` switch)
- Modify: `ElementX/Sources/Screens/Timeline/View/Replies/TimelineReplyView.swift`
- Modify: `ElementX/Sources/Screens/Timeline/View/Threads/TimelineThreadSummaryView.swift`

**Interfaces:**
- Consumes: `AgentChoiceRequestRoomTimelineItemContent` (Task 1).
- Produces: `AgentChoiceRequestRoomTimelineItem: EventBasedMessageTimelineItemProtocol, Equatable`; `EventBasedMessageTimelineItemContentType.choiceRequest(AgentChoiceRequestRoomTimelineItemContent)`.

This task has no test of its own — it's registration/plumbing verified by the whole-scheme build compiling (an exhaustive switch you forget to update is a compile error, which is the test).

- [ ] **Step 1: Create the timeline item**

Create `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentChoiceRequestRoomTimelineItem.swift`:

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct AgentChoiceRequestRoomTimelineItem: EventBasedMessageTimelineItemProtocol, Equatable {
    let id: TimelineItemIdentifier
    let timestamp: Date
    let isOutgoing: Bool
    let isEditable: Bool
    let canBeRepliedTo: Bool
    
    let sender: TimelineItemSender
    
    let content: AgentChoiceRequestRoomTimelineItemContent
    
    var properties = RoomTimelineItemProperties()
    
    var body: String {
        content.body
    }
    
    var contentType: EventBasedMessageTimelineItemContentType {
        .choiceRequest(content)
    }
}
```

- [ ] **Step 2: Register the new case in `EventBasedMessageTimelineItemContentType` and its three switches**

In `ElementX/Sources/Services/Timeline/TimelineItems/EventBasedMessageTimelineItemProtocol.swift`, add the case (currently lines 11-22):

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
    case choiceRequest(AgentChoiceRequestRoomTimelineItemContent)
}
```

Then add `.choiceRequest` alongside `.agentTurn` in each of the three switches in the same file (currently lines 28-71):

```swift
nonisolated extension EventBasedMessageTimelineItemProtocol {
    var supportsMediaCaption: Bool {
        switch contentType {
        case .audio, .file, .image, .video:
            true
        case .emote, .notice, .text, .location, .voice, .agentTurn, .choiceRequest:
            false
        }
    }
    
    var hasMediaCaption: Bool {
        mediaCaption != nil
    }
    
    var mediaCaption: String? {
        switch contentType {
        case .audio(let content):
            content.caption
        case .file(let content):
            content.caption
        case .image(let content):
            content.caption
        case .video(let content):
            content.caption
        case .emote, .notice, .text, .location, .voice, .agentTurn, .choiceRequest:
            nil
        }
    }
    
    var formattedMediaCaption: AttributedString? {
        switch contentType {
        case .audio(let content):
            content.formattedCaption
        case .file(let content):
            content.formattedCaption
        case .image(let content):
            content.formattedCaption
        case .video(let content):
            content.formattedCaption
        case .emote, .notice, .text, .location, .voice, .agentTurn, .choiceRequest:
            nil
        }
    }
}
```

- [ ] **Step 3: Register in `isCopyable`**

In `ElementX/Sources/Services/Timeline/TimelineItems/EventBasedTimelineItemProtocol.swift`, currently lines 100-110:

```swift
    var isCopyable: Bool {
        guard let messageBasedItem = self as? EventBasedMessageTimelineItemProtocol else {
            return false
        }
        
        switch messageBasedItem.contentType {
        case .audio, .file, .image, .video, .location, .voice:
            return false
        case .text, .emote, .notice, .agentTurn, .choiceRequest:
            return true
        }
    }
```

- [ ] **Step 4: Register the reply preview**

In `ElementX/Sources/Screens/Timeline/View/Replies/TimelineReplyView.swift`, find the existing `case .agentTurn(let content):` (currently around line 87) and add a case right after it:

```swift
                    case .agentTurn(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.body,
                                  formattedBody: nil)
                    case .choiceRequest(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.question.isEmpty ? content.body : content.question,
                                  formattedBody: nil)
```

- [ ] **Step 5: Register the thread summary**

In `ElementX/Sources/Screens/Timeline/View/Threads/TimelineThreadSummaryView.swift`, find the existing `case .agentTurn(let content):` (currently around line 85) and add a case right after it, matching that block's exact shape (read the surrounding `ThreadView(senderID:sender:plainBody:numberOfReplies:)` call before writing this — the exact parameter list must match the neighboring `.agentTurn` case in the file you're editing):

```swift
                case .choiceRequest(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.question.isEmpty ? content.body : content.question,
                               numberOfReplies: numberOfReplies)
```

- [ ] **Step 6: Build the whole scheme**

Run over SSH on the Mac: `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>'`
Expected: `** BUILD SUCCEEDED **`. If it fails with an exhaustive-switch error in a file not listed above, that's a real additional case this plan's Global Constraints section didn't anticipate — fix it and note the extra file in your report.

- [ ] **Step 7: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentChoiceRequestRoomTimelineItem.swift \
        ElementX/Sources/Services/Timeline/TimelineItems/EventBasedMessageTimelineItemProtocol.swift \
        ElementX/Sources/Services/Timeline/TimelineItems/EventBasedTimelineItemProtocol.swift \
        ElementX/Sources/Screens/Timeline/View/Replies/TimelineReplyView.swift \
        ElementX/Sources/Screens/Timeline/View/Threads/TimelineThreadSummaryView.swift
git commit -m "Register AgentChoiceRequestRoomTimelineItem's content type across exhaustive switches"
```

---

## Task 3: `RoomTimelineItemViewState`/`RoomTimelineItemType` registration

**Files:**
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemViewState.swift`

**Interfaces:**
- Consumes: `AgentChoiceRequestRoomTimelineItem` (Task 2).
- Produces: `RoomTimelineItemType.choiceRequest(AgentChoiceRequestRoomTimelineItem)`.

This task has no test of its own — same reasoning as Task 2, verified by the build.

- [ ] **Step 1: Add the case and its three switch sites**

In `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemViewState.swift`:

Add to the `RoomTimelineItemType` enum (currently lines 49-73, right after `case agentTurn(AgentTurnRoomTimelineItem)` at line 68):

```swift
    case agentTurn(AgentTurnRoomTimelineItem)
    case choiceRequest(AgentChoiceRequestRoomTimelineItem)
    case poll(PollRoomTimelineItem)
```

Add to `init(item:)`'s dispatch (currently lines 75-128, right after the `AgentTurnRoomTimelineItem` case at lines 113-114):

```swift
        case let item as AgentTurnRoomTimelineItem:
            self = .agentTurn(item)
        case let item as AgentChoiceRequestRoomTimelineItem:
            self = .choiceRequest(item)
        case let item as PollRoomTimelineItem:
            self = .poll(item)
```

Add to the `id` switch's pattern-matching case list (currently lines 130-158, right after `.agentTurn(let item as RoomTimelineItemProtocol),` at line 150):

```swift
             .agentTurn(let item as RoomTimelineItemProtocol),
             .choiceRequest(let item as RoomTimelineItemProtocol),
             .poll(let item as RoomTimelineItemProtocol),
```

Add to the `timestamp` switch (currently lines 164-211, right after `case .agentTurn(let item): return item.timestamp` at lines 194-195):

```swift
        case .agentTurn(let item):
            return item.timestamp
        case .choiceRequest(let item):
            return item.timestamp
        case .poll(let item):
            return item.timestamp
```

- [ ] **Step 2: Build the whole scheme**

Run over SSH on the Mac: `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>'`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemViewState.swift
git commit -m "Register AgentChoiceRequestRoomTimelineItem in RoomTimelineItemViewState"
```

---

## Task 4: `RoomTimelineItemFactory` interception and mock fixture

**Files:**
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemFactory.swift`
- Modify: `ElementX/Sources/Mocks/SDK/EventTimelineItem.swift`

**Interfaces:**
- Consumes: `AgentChoiceRequestRoomTimelineItem`/`AgentChoiceRequestRoomTimelineItemContent` (Tasks 1-2).
- Produces: `EventTimelineItem.mockChoiceRequest(sender:body:question:options:multiSelect:originalJSON:latestEditJSON:) -> EventTimelineItem`.

This task has no test of its own — exercised indirectly by Task 5's `TestablePreview` snapshot tests, which is how `mockAgentTurn` is exercised today.

- [ ] **Step 1: Extend the factory's `.other` interception to handle two msgtypes**

In `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemFactory.swift`, the current interception (lines 106-109) only recognizes one custom msgtype:

```swift
        case .other(let msgtype, let body):
            guard msgtype == AgentTurnRoomTimelineItemContent.msgType else { return nil }
            return buildAgentTurnTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, body, isOutgoing)
```

Replace it with a dispatch over both known custom msgtypes:

```swift
        case .other(let msgtype, let body):
            switch msgtype {
            case AgentTurnRoomTimelineItemContent.msgType:
                return buildAgentTurnTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, body, isOutgoing)
            case AgentChoiceRequestRoomTimelineItemContent.msgType:
                return buildChoiceRequestTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, body, isOutgoing)
            default:
                return nil
            }
```

- [ ] **Step 2: Add the builder function**

In the same file, add a new private function right after `buildAgentTurnTimelineItem` (currently ending at line 345):

```swift
    private func buildChoiceRequestTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                                _ messageLikeContent: MsgLikeContent,
                                                _ messageContent: MessageContent,
                                                _ body: String,
                                                _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        AgentChoiceRequestRoomTimelineItem(id: eventItemProxy.id,
                                           timestamp: eventItemProxy.timestamp,
                                           isOutgoing: isOutgoing,
                                           isEditable: eventItemProxy.isEditable,
                                           canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                           sender: eventItemProxy.sender,
                                           content: .init(body: body,
                                                         parsingFrom: eventItemProxy.debugInfo.originalJSON,
                                                         latestEditJSON: eventItemProxy.debugInfo.latestEditJSON),
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

- [ ] **Step 3: Add the mock fixture**

In `ElementX/Sources/Mocks/SDK/EventTimelineItem.swift`, add right after `mockAgentTurn` (currently ending at line 89):

```swift
    static func mockChoiceRequest(sender: String = "",
                                  body: String = "Which environment?",
                                  question: String = "Which environment?",
                                  options: [(id: String, label: String)] = [("test", "Test"), ("prod", "Production")],
                                  multiSelect: Bool = false,
                                  originalJSON: String? = nil,
                                  latestEditJSON: String? = nil) -> EventTimelineItem {
        let messageType = MessageType.other(msgtype: AgentChoiceRequestRoomTimelineItemContent.msgType, body: body)
        
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        
        let optionsJSONArray = options.map { "{\"id\":\"\($0.id)\",\"label\":\"\($0.label)\"}" }.joined(separator: ",")
        let defaultOriginalJSON = originalJSON ?? """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"\(body)","question":"\(question)",\
        "options":[\(optionsJSONArray)],"multi_select":\(multiSelect)}}
        """
        
        return .init(configuration: .init(sender: sender, content: content, originalJSON: defaultOriginalJSON))
    }
```

Note: this fixture only threads `originalJSON` through `EventTimelineItemSDKMockConfiguration` (matching what that struct already supports, see `EventTimelineItem.swift:14-29`) — it does not add `latestEditJSON` support to the mock configuration, since Task 5's previews only need unresolved and resolved states, and a resolved state can be constructed by passing a pre-resolved `originalJSON` directly (with `resolved_selection` already present) rather than needing a genuine two-JSON edit simulation in the mock layer.

- [ ] **Step 4: Build the whole scheme**

Run over SSH on the Mac: `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>'`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemFactory.swift \
        ElementX/Sources/Mocks/SDK/EventTimelineItem.swift
git commit -m "Intercept io.element.agent.choice_request in RoomTimelineItemFactory"
```

---

## Task 5: `AgentChoiceRequestRoomTimelineView` and send wiring

**Files:**
- Create: `ElementX/Sources/Screens/Timeline/View/TimelineItemViews/AgentChoiceRequestRoomTimelineView.swift`
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemView.swift`
- Modify: `ElementX/Sources/Screens/Timeline/TimelineModels.swift`
- Modify: `ElementX/Sources/Screens/Timeline/TimelineViewModel.swift`
- Modify: `ElementX/Sources/Screens/Timeline/TimelineInteractionHandler.swift`
- Modify: `ElementX/Resources/Localizations/en.lproj/Untranslated.strings`

**Interfaces:**
- Consumes: `AgentChoiceRequestRoomTimelineItem` (Task 2), `TimelineControllerProtocol.sendMessage(_:html:inReplyToEventID:intentionalMentions:)` (existing), `IntentionalMentions.empty` (existing, `IntentionalMentions.swift:19-20`).
- Produces: `AgentChoiceRequestRoomTimelineView: View`; `TimelineViewChoiceRequestAction` enum; `TimelineViewAction.handleChoiceRequestAction(TimelineViewChoiceRequestAction)`.

This task's interaction logic (single-select immediate-send, multi-select toggle-then-confirm, resolved static display) has no isolated unit test — it's pure SwiftUI state plus one action dispatch, covered by `TestablePreview`-generated snapshot/accessibility tests across three preview states (unanswered single-select, unanswered multi-select with a partial selection, resolved).

- [ ] **Step 1: Add the new strings**

Add to `ElementX/Resources/Localizations/en.lproj/Untranslated.strings` (append near the other `agent_turn`/agent-related entries):

```
"screen_room_timeline_agent_choice_confirm_button" = "Confirm";
"screen_room_timeline_agent_choice_selected_prefix" = "Selected";
```

Run `swiftgen config run --config Tools/SwiftGen/swiftgen-config.yml` on the Mac to regenerate `Strings+Untranslated.swift`; confirm `UntranslatedL10n.screenRoomTimelineAgentChoiceConfirmButton` and `UntranslatedL10n.screenRoomTimelineAgentChoiceSelectedPrefix` appear (`grep -n 'AgentChoice' ElementX/Sources/Generated/Strings+Untranslated.swift`).

- [ ] **Step 2: Add the `TimelineViewChoiceRequestAction` enum and wire the view action**

In `ElementX/Sources/Screens/Timeline/TimelineModels.swift`, add a new enum right after `TimelineViewPollAction` (currently lines 38-42):

```swift
enum TimelineViewPollAction {
    case sendResponse(pollStartID: String, answerIDs: [String])
    case end(pollStartID: String)
    case edit(pollStartID: String, poll: Poll)
}

enum TimelineViewChoiceRequestAction {
    case sendResponse(requestEventID: String, body: String)
}
```

Add a case to `TimelineViewAction` right after `case handlePollAction(TimelineViewPollAction)` (currently line 75):

```swift
    case handlePollAction(TimelineViewPollAction)
    case handleChoiceRequestAction(TimelineViewChoiceRequestAction)
```

- [ ] **Step 3: Handle the action in `TimelineViewModel`**

In `ElementX/Sources/Screens/Timeline/TimelineViewModel.swift`, find `case .handlePollAction(let pollAction): handlePollAction(pollAction)` (currently line 211-212) and add a case right after it:

```swift
        case .handlePollAction(let pollAction):
            handlePollAction(pollAction)
        case .handleChoiceRequestAction(let choiceRequestAction):
            handleChoiceRequestAction(choiceRequestAction)
```

Add the handler function right after `handlePollAction` (currently ending at line 386):

```swift
    private func handleChoiceRequestAction(_ action: TimelineViewChoiceRequestAction) {
        switch action {
        case let .sendResponse(requestEventID, body):
            timelineInteractionHandler.sendChoiceRequestResponse(requestEventID: requestEventID, body: body)
        }
    }
```

- [ ] **Step 4: Send the reply in `TimelineInteractionHandler`**

In `ElementX/Sources/Screens/Timeline/TimelineInteractionHandler.swift`, add a new function right after `sendPollResponse` (currently ending at line 262). This calls `timelineController.sendMessage(_:html:inReplyToEventID:intentionalMentions:)` — verified against `TimelineController.swift:289-304` and `TimelineViewModel.swift:771-774,791-794`, which is the actual, real send-a-reply path this codebase uses (not `roomProxy.timeline.sendMessage` directly, which nothing in production code calls). Unlike `TimelineProxyProtocol.sendMessage`, `TimelineControllerProtocol.sendMessage` (`TimelineControllerProtocol.swift:100-103`) returns no `Result` — the controller already logs failures internally (`TimelineController.swift:303-304`) and does not surface them to its caller, so there is nothing to switch on here:

```swift
    func sendChoiceRequestResponse(requestEventID: String, body: String) {
        Task {
            await timelineController.sendMessage(body,
                                                 html: nil,
                                                 inReplyToEventID: requestEventID,
                                                 intentionalMentions: .empty)
        }
    }
```

- [ ] **Step 5: Create the SwiftUI view**

Create `ElementX/Sources/Screens/Timeline/View/TimelineItemViews/AgentChoiceRequestRoomTimelineView.swift`:

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct AgentChoiceRequestRoomTimelineView: View {
    let timelineItem: AgentChoiceRequestRoomTimelineItem
    
    @EnvironmentObject private var context: TimelineViewModel.Context
    @State private var pendingSelection: Set<String> = []
    
    private var content: AgentChoiceRequestRoomTimelineItemContent {
        timelineItem.content
    }
    
    private var eventID: String? {
        timelineItem.id.eventID
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            VStack(alignment: .leading, spacing: 8) {
                Text(content.question.isEmpty ? content.body : content.question)
                    .font(.compound.bodyMD)
                    .foregroundColor(.compound.textPrimary)
                
                if let resolvedSelection = content.resolvedSelection {
                    resolvedView(selectedIDs: resolvedSelection)
                } else if content.multiSelect {
                    multiSelectView
                } else {
                    singleSelectView
                }
            }
        }
    }
    
    private var singleSelectView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(content.options, id: \.id) { option in
                Button(option.label) {
                    send(selectedIDs: [option.id])
                }
                .buttonStyle(.compound(.secondary, size: .medium))
            }
        }
    }
    
    private var multiSelectView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(content.options, id: \.id) { option in
                Button {
                    toggle(option.id)
                } label: {
                    HStack {
                        if pendingSelection.contains(option.id) {
                            CompoundIcon(\.checkCircleSolid, size: .small, relativeTo: .compound.bodyMD)
                        } else {
                            CompoundIcon(\.circle, size: .small, relativeTo: .compound.bodyMD)
                        }
                        Text(option.label)
                    }
                }
                .buttonStyle(.compound(.secondary, size: .medium))
            }
            
            Button(UntranslatedL10n.screenRoomTimelineAgentChoiceConfirmButton) {
                send(selectedIDs: pendingSelection)
            }
            .buttonStyle(.compound(.primary, size: .medium))
            .disabled(pendingSelection.isEmpty)
        }
    }
    
    private func resolvedView(selectedIDs: [String]) -> some View {
        let labels = selectedIDs.compactMap { id in content.options.first { $0.id == id }?.label }
        return Text("\(UntranslatedL10n.screenRoomTimelineAgentChoiceSelectedPrefix): \(labels.joined(separator: ", "))")
            .font(.compound.bodySM)
            .foregroundColor(.compound.textSecondary)
    }
    
    private func toggle(_ optionID: String) {
        if pendingSelection.contains(optionID) {
            pendingSelection.remove(optionID)
        } else {
            pendingSelection.insert(optionID)
        }
    }
    
    private func send(selectedIDs: Set<String>) {
        guard let eventID else { return }
        let labels = content.options.filter { selectedIDs.contains($0.id) }.map(\.label)
        let body = "\(UntranslatedL10n.screenRoomTimelineAgentChoiceSelectedPrefix):\n" + labels.map { "• \($0)" }.joined(separator: "\n")
        context.send(viewAction: .handleChoiceRequestAction(.sendResponse(requestEventID: eventID, body: body)))
    }
}

struct AgentChoiceRequestRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock
    
    static var previews: some View {
        PreviewScrollView {
            VStack(spacing: 8) {
                states
            }
        }
        .previewLayout(.sizeThatFits)
        .environmentObject(viewModel.context)
    }
    
    @ViewBuilder
    static var states: some View {
        AgentChoiceRequestRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                               timestamp: .mock,
                                                               isOutgoing: false,
                                                               isEditable: false,
                                                               canBeRepliedTo: true,
                                                               sender: .init(id: "@agent:example.com"),
                                                               content: .init(body: "Which environment?",
                                                                              question: "Which environment should this deploy to?",
                                                                              options: [ChoiceOption(id: "test", label: "Test"),
                                                                                       ChoiceOption(id: "staging", label: "Staging"),
                                                                                       ChoiceOption(id: "prod", label: "Production")],
                                                                              multiSelect: false)))
        
        AgentChoiceRequestRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                               timestamp: .mock,
                                                               isOutgoing: false,
                                                               isEditable: false,
                                                               canBeRepliedTo: true,
                                                               sender: .init(id: "@agent:example.com"),
                                                               content: .init(body: "Which reviewers?",
                                                                              question: "Which reviewers should be added?",
                                                                              options: [ChoiceOption(id: "a", label: "Alice"),
                                                                                       ChoiceOption(id: "b", label: "Bob")],
                                                                              multiSelect: true)))
        
        AgentChoiceRequestRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                               timestamp: .mock,
                                                               isOutgoing: false,
                                                               isEditable: false,
                                                               canBeRepliedTo: true,
                                                               sender: .init(id: "@agent:example.com"),
                                                               content: .init(body: "Which environment?",
                                                                              question: "Which environment should this deploy to?",
                                                                              options: [ChoiceOption(id: "test", label: "Test"),
                                                                                       ChoiceOption(id: "staging", label: "Staging"),
                                                                                       ChoiceOption(id: "prod", label: "Production")],
                                                                              multiSelect: false,
                                                                              resolvedSelection: ["staging"])))
    }
}
```

- [ ] **Step 6: Wire the dispatch in `RoomTimelineItemView.swift`**

Find the existing `case .agentTurn(let item): AgentTurnRoomTimelineView(timelineItem: item)` (currently lines 67-68) and add a case right after it:

```swift
        case .agentTurn(let item):
            AgentTurnRoomTimelineView(timelineItem: item)
        case .choiceRequest(let item):
            AgentChoiceRequestRoomTimelineView(timelineItem: item)
        case .poll(let item):
            PollRoomTimelineView(timelineItem: item)
```

- [ ] **Step 7: Regenerate Sourcery-derived test files**

Run on the Mac: `sourcery --config Tools/Sourcery/PreviewTestsConfig.yml && sourcery --config Tools/Sourcery/TestablePreviewsDictionary.yml && sourcery --config Tools/Sourcery/AccessibilityTests.yml`
Expected: `PreviewTests/Sources/GeneratedPreviewTests.swift`, `ElementX/Sources/Other/TestablePreview/TestablePreviewsDictionary.swift`, and `AccessibilityTests/Sources/GeneratedAccessibilityTests.swift` all gain new generated test functions for `AgentChoiceRequestRoomTimelineView_Previews`.

- [ ] **Step 8: Build and run the generated snapshot test**

Run: `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>'`
Expected: `** BUILD SUCCEEDED **`.

Then, following this session's established recording procedure: toggle `RECORD_FAILURES` to `enabled: true` in `PreviewTests/SupportingFiles/PreviewTests.xctestplan`, run `xcodebuild test -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>' -only-testing:'PreviewTests/PreviewTests/agentChoiceRequestRoomTimelineView()'` (adjust the exact generated test identifier to whatever Step 7 produced) to record reference snapshots for all three preview states, then toggle `RECORD_FAILURES` back to `false` and `git checkout --` that file so the toggle itself is never committed. Re-run the same test once more without recording to confirm the new references are stable.
Expected: PASS.

- [ ] **Step 9: Verify the pbxproj registration and xcodegen**

Since this task creates a new file, run `/opt/homebrew/bin/xcodegen` on the Mac after your `git pull`, confirm `grep -c 'AgentChoiceRequestRoomTimelineView' ElementX.xcodeproj/project.pbxproj` is nonzero, and if `xcodegen` changed `project.pbxproj`, pull that change back to this Linux repo and commit it alongside the rest of this task (not as Mac-local-only state).

- [ ] **Step 10: Commit**

```bash
git add ElementX/Sources/Screens/Timeline/View/TimelineItemViews/AgentChoiceRequestRoomTimelineView.swift \
        ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemView.swift \
        ElementX/Sources/Screens/Timeline/TimelineModels.swift \
        ElementX/Sources/Screens/Timeline/TimelineViewModel.swift \
        ElementX/Sources/Screens/Timeline/TimelineInteractionHandler.swift \
        ElementX/Resources/Localizations/en.lproj/Untranslated.strings \
        ElementX/Sources/Generated/Strings+Untranslated.swift \
        PreviewTests/Sources/GeneratedPreviewTests.swift \
        ElementX/Sources/Other/TestablePreview/TestablePreviewsDictionary.swift \
        AccessibilityTests/Sources/GeneratedAccessibilityTests.swift \
        PreviewTests/Sources/__Snapshots__/PreviewTests/agentChoiceRequestRoomTimelineView.*
git commit -m "Add AgentChoiceRequestRoomTimelineView with single/multi-select send wiring"
```

---

## Self-Review Notes

- **Spec coverage:** every decision in `docs/superpowers/specs/2026-07-04-agent-choice-request-design.md` is covered — new msgtype + card (Tasks 1-2, 4-5), no canvas (the whole plan is timeline-only), no per-user targeting (the view has no authorization check, by design), most-recent-answer-wins (the client never aggregates; it only ever reads whatever `resolved_selection` its own event's latest content currently has), plain-`m.text`-reply-with-fixed-body-format (Task 5 Step 5's `send(selectedIDs:)`, no custom JSON field anywhere), resolution via message edit read locally (Task 1's dual-JSON parsing, no cross-event queries), single-select-immediate vs. multi-select-toggle-then-confirm (Task 5's `singleSelectView`/`multiSelectView`).
- **Placeholder scan:** no TBD/TODO; every step has complete, concrete code or exact commands.
- **Type consistency:** `AgentChoiceRequestRoomTimelineItemContent`, `ChoiceOption`, `AgentChoiceRequestRoomTimelineItem`, `.choiceRequest` case name, and `TimelineViewChoiceRequestAction` are named identically everywhere they're referenced across all 5 tasks.
- **Deviation from the spec's illustrative wire JSON, made deliberately and documented in Global Constraints:** field names are `snake_case` (`multi_select`, `resolved_selection`) rather than the spec's camelCase, to match `io.element.agent.turn`'s established `tool_calls` convention — verified directly against `AgentTurnRoomTimelineItemContent.swift`'s `CodingKeys` before writing this plan, not assumed.
- **Named, upfront-flagged uncertainty:** whether `latestEditJSON` needs the `m.new_content` unwrap or not could not be resolved from the vendored SDK bindings (checked directly: `matrix_sdk_ffi.swift`'s `EventTimelineItemDebugInfo` struct has no doc comments) or any existing test in this codebase. Task 1's parser handles both hypotheses defensively and its test suite exercises both; Task 1 Step 5 requires empirical confirmation against a real edited event before the task reports DONE, rather than shipping on an unverified guess.
- **Verified against real code, not guessed:** every file path, line range, and neighboring-code shape referenced above (the `.agentTurn` case's exact locations across `RoomTimelineItemFactory.swift`, `RoomTimelineItemViewState.swift`, `EventBasedMessageTimelineItemProtocol.swift`, `EventBasedTimelineItemProtocol.swift`, `TimelineReplyView.swift`, `TimelineThreadSummaryView.swift`, `RoomTimelineItemView.swift`; `PollRoomTimelineView.swift`'s `context.send(viewAction:)` pattern via `TimelineViewChoiceRequestAction`/`TimelineViewPollAction`; `TimelineInteractionHandler.swift`'s existing `timelineController: TimelineControllerProtocol` dependency and `sendPollResponse`'s `Task { ... }` shape; `IntentionalMentions.empty`) were read directly from the current source before writing this plan, not inferred from the design doc alone.
- **A real send-path correction made during self-review, not shipped as an initial guess:** the first draft of Task 5 Step 4 called `roomProxy.timeline.sendMessage(...)` and switched on a returned `Result`, mirroring `sendPollResponse`'s shape too literally. Grepping for actual production callers of `.sendMessage(` found nothing calling `roomProxy.timeline.sendMessage` directly — the real path, used by `TimelineViewModel.sendCurrentMessage` itself (`TimelineViewModel.swift:771-774,791-794`), is `timelineController.sendMessage(...)`, which returns no `Result` at all (`TimelineControllerProtocol.swift:100-103`) since `TimelineController`'s own implementation already logs failures internally (`TimelineController.swift:289-304`) rather than propagating them. Task 5 Step 4 now reflects the verified, real API.
