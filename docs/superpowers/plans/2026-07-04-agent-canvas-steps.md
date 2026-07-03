# Agent Canvas V1 (Step Tracker) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first canvas content type — a flat step-tracker checklist — reachable via a new `RoomScreen` banner, backed by a new `io.element.agent.canvas.steps` message type.

**Architecture:** The message type follows the exact 5-extension-point path `io.element.agent.turn`/`io.element.agent.choice_request` already proved (content model parsing `originalJSON`/`latestEditJSON`, timeline item, `EventBasedMessageTimelineItemContentType` registration, `RoomTimelineItemFactory` interception, a minimal inline `TimelineStyler`-wrapped card). On top of that, `TimelineViewState` gains a computed "is there an active canvas task" signal (derived from `timelineController.timelineItems`, the same data `TimelineViewModel` already scans to build its rendered rows), a new `CanvasTaskBannerView` renders in `RoomScreen`'s existing banner stack reading that signal directly from the already-in-scope `timelineContext`, and tapping it flows `TimelineViewAction` → `TimelineViewModelAction` → `RoomScreenCoordinatorAction` → a new `RoomFlowCoordinatorStateMachine` state/event pushing a new `CanvasStepsScreen` (full 5-file MVVM-C, with a `Coordinator` this time since it's pushed via `navigationStackCoordinator.push(coordinator:...)`, not presented as a sheet).

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing (`@Test`/`#expect`), Compound, SwiftState (`StateMachine<State, Event>`), Sourcery-generated `TestablePreview` snapshot/accessibility tests.

## Global Constraints

- This Linux machine has no local Swift/Xcode toolchain — every build/test runs over SSH on a remote Mac (`ssh -i ~/.ssh/id_ed25519_kaka zhangqiong@mac-mini.tail2edbaa.ts.net "cd ~/Code/element-x-ios && <command>"`). Implement and commit locally on Linux, push to `coderkaka feature/space-tab-bar`, then SSH to the Mac to pull, build, and test.
- New files must be registered in `ElementX.xcodeproj/project.pbxproj` — run `/opt/homebrew/bin/xcodegen` on the Mac after pulling and verify via `grep -c '<NewFileName>' ElementX.xcodeproj/project.pbxproj` (nonzero). If `xcodegen` changes `project.pbxproj`, pull that change back to this Linux repo and commit it — do not leave it Mac-local-only. This has recurred in nearly every prior task this session.
- New or changed `TestablePreview`/`PreviewProvider` types need Sourcery regeneration: `sourcery --config Tools/Sourcery/PreviewTestsConfig.yml && sourcery --config Tools/Sourcery/TestablePreviewsDictionary.yml && sourcery --config Tools/Sourcery/AccessibilityTests.yml` — commit the regenerated output.
- `Untranslated.strings` entries generate into a separate `UntranslatedL10n` enum (`ElementX/Sources/Generated/Strings+Untranslated.swift`), not the main `L10n` enum. Any new user-facing string in this plan goes in `ElementX/Resources/Localizations/en.lproj/Untranslated.strings` and is consumed as `UntranslatedL10n.*`.
- Wire field names are `snake_case` (`task_id`), matching the established `tool_calls`/`multi_select`/`resolved_selection` convention.
- **The `latestEditJSON` shape question is already resolved** — confirmed this session (`io.element.agent.choice_request`'s Task 1, independently re-verified by its task reviewer against live `matrix-rust-sdk` source) to be the raw `m.replace` edit event, fields nested under `m.new_content`. Task 1 of this plan reuses that confirmed shape directly; there is no need to write dual-hypothesis tests or redo the empirical verification.
- Any change to `EventBasedMessageTimelineItemContentType` is exhaustively switched over in **six** places, per the pattern already mapped out for `io.element.agent.choice_request`: `EventBasedMessageTimelineItemProtocol.swift` (3 switches), `EventBasedTimelineItemProtocol.swift` (`isCopyable`), `TimelineReplyView.swift`, `TimelineThreadSummaryView.swift` (all four covered by Task 2, none reference the concrete view type), `RoomTimelineItemViewState.swift` (Task 3), `RoomTimelineItemView.swift` (Task 5, since it does reference the concrete view type).
- The msgtype string is `io.element.agent.canvas.steps`, defined once as `AgentCanvasStepsRoomTimelineItemContent.msgType`.
- `RoomTimelineItemFactory.swift`'s `.other(msgtype, body)` case now dispatches over **three** known custom msgtypes (`io.element.agent.turn`, `io.element.agent.choice_request`, `io.element.agent.canvas.steps`) — Task 4 extends the existing `switch msgtype { case ...: ...; case ...: ...; default: return nil }` shape choice-request's Task 4 already established, adding one more case, not restructuring what's there.
- Canvas V1 is read-only from the client's perspective — no task in this plan sends any Matrix event. All writes (the initial canvas-steps message, its progress-update edits) come from the agent backend, external to this plan.

---

## Task 1: `AgentCanvasStepsRoomTimelineItemContent` model and JSON parsing

**Files:**
- Create: `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentCanvasStepsRoomTimelineItemContent.swift`
- Test: `UnitTests/Sources/AgentCanvasStepsRoomTimelineItemContentTests.swift`

**Interfaces:**
- Produces: `CanvasStep: Hashable, Decodable` (`id: String`; `label: String`; `status: CanvasStep.Status`, an enum `pending`/`inProgress`/`done`/`other(String)` mirroring `ToolCallSummary.Status`'s forward-compat pattern in `AgentTurnRoomTimelineItemContent.swift:12-19,28-38`); `AgentCanvasStepsRoomTimelineItemContent: Hashable` (`static let msgType = "io.element.agent.canvas.steps"`; `body: String`; `taskID: String`; `title: String`; `isResolved: Bool` — true when the top-level `status` field is `"done"`; `steps: [CanvasStep]`); `init(body:parsingFrom:latestEditJSON:)`.

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/Sources/AgentCanvasStepsRoomTimelineItemContentTests.swift`:

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

struct AgentCanvasStepsRoomTimelineItemContentTests {
    @Test
    func parsesWellFormedInProgressTask() {
        let json = """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"Task: Refactor auth module",
        "task_id":"task-1234","title":"Refactor auth module","status":"in_progress",
        "steps":[{"id":"step1","label":"Read existing code","status":"done"},
        {"id":"step2","label":"Wait for approval","status":"in_progress"},
        {"id":"step3","label":"Run tests","status":"pending"}]}}
        """
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "Task: Refactor auth module", parsingFrom: json, latestEditJSON: nil)
        #expect(content.taskID == "task-1234")
        #expect(content.title == "Refactor auth module")
        #expect(content.isResolved == false)
        #expect(content.steps == [CanvasStep(id: "step1", label: "Read existing code", status: .done),
                                  CanvasStep(id: "step2", label: "Wait for approval", status: .inProgress),
                                  CanvasStep(id: "step3", label: "Run tests", status: .pending)])
    }
    
    @Test
    func unknownStepStatusIsPreservedAsOther() {
        let json = """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"fallback","task_id":"t","title":"T","status":"in_progress",
        "steps":[{"id":"s1","label":"L","status":"blocked"}]}}
        """
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: json, latestEditJSON: nil)
        #expect(content.steps == [CanvasStep(id: "s1", label: "L", status: .other("blocked"))])
    }
    
    @Test
    func missingStepsFieldFallsBackToEmpty() {
        let json = """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"fallback","task_id":"t","title":"T","status":"in_progress"}}
        """
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: json, latestEditJSON: nil)
        #expect(content.steps.isEmpty)
        #expect(content.title == "T")
    }
    
    @Test
    func malformedStepEntryFallsBackToEmptySteps() {
        let json = """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"fallback","task_id":"t","title":"T","status":"in_progress",
        "steps":[{"id":"s1"}]}}
        """
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: json, latestEditJSON: nil)
        #expect(content.steps.isEmpty)
        #expect(content.title == "T")
    }
    
    @Test
    func nilOriginalJSONFallsBackToEmptyDefaults() {
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: nil, latestEditJSON: nil)
        #expect(content.taskID.isEmpty)
        #expect(content.title.isEmpty)
        #expect(content.isResolved == false)
        #expect(content.steps.isEmpty)
    }
    
    @Test
    func unresolvedTaskHasInProgressStatus() {
        let json = """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"fallback","task_id":"t","title":"T","status":"in_progress",
        "steps":[]}}
        """
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: json, latestEditJSON: nil)
        #expect(content.isResolved == false)
    }
    
    @Test
    func editedTaskWithDoneStatusIsResolved() {
        // latestEditJSON's shape is confirmed this session: raw m.replace edit event, replacement fields
        // nested under m.new_content (see AgentChoiceRequestRoomTimelineItemContent's own confirmed parsing).
        let original = """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"fallback","task_id":"t","title":"T","status":"in_progress",
        "steps":[{"id":"s1","label":"L","status":"in_progress"}]}}
        """
        let edit = """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"* Done","
        m.new_content":{"msgtype":"io.element.agent.canvas.steps","body":"Done","task_id":"t","title":"T","status":"done",
        "steps":[{"id":"s1","label":"L","status":"done"}]},
        "m.relates_to":{"rel_type":"m.replace","event_id":"$original"}}}
        """
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: original, latestEditJSON: edit)
        #expect(content.isResolved == true)
        #expect(content.steps == [CanvasStep(id: "s1", label: "L", status: .done)])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run over SSH on the Mac: `xcodebuild test -project ElementX.xcodeproj -scheme UnitTests -destination 'platform=iOS Simulator,id=<current simulator id>' -only-testing:UnitTests/AgentCanvasStepsRoomTimelineItemContentTests`
Expected: FAIL (build error — types don't exist yet).

- [ ] **Step 3: Write the implementation**

Create `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentCanvasStepsRoomTimelineItemContent.swift`:

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct CanvasStep: Hashable, Decodable {
    enum Status: Hashable {
        case pending
        case inProgress
        case done
        /// Any status value the client doesn't recognise yet — kept instead of dropped so a future
        /// agent backend can introduce new statuses without this client silently losing data.
        case other(String)
    }
    
    let id: String
    let label: String
    let status: Status
}

extension CanvasStep.Status: Decodable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "pending": self = .pending
        case "in_progress": self = .inProgress
        case "done": self = .done
        default: self = .other(raw)
        }
    }
}

nonisolated struct AgentCanvasStepsRoomTimelineItemContent: Hashable {
    /// The custom `m.room.message` msgtype this content type is built from.
    static let msgType = "io.element.agent.canvas.steps"
    
    let body: String
    let taskID: String
    let title: String
    let isResolved: Bool
    let steps: [CanvasStep]
    
    init(body: String, taskID: String = "", title: String = "", isResolved: Bool = false, steps: [CanvasStep] = []) {
        self.body = body
        self.taskID = taskID
        self.title = title
        self.isResolved = isResolved
        self.steps = steps
    }
    
    /// - Parameters:
    ///   - originalJSON: the raw Matrix event JSON from `EventTimelineItemProxy.debugInfo.originalJSON`.
    ///     The Rust SDK only exposes `body` for custom msgtypes via `MessageType.other`, so
    ///     `task_id`/`title`/`status`/`steps` have to be recovered by hand, same reasoning
    ///     `AgentTurnRoomTimelineItemContent` documents for `tool_calls`.
    ///   - latestEditJSON: `EventTimelineItemProxy.debugInfo.latestEditJSON`, non-nil once the agent
    ///     has edited this message to update progress. Confirmed this session (via
    ///     `io.element.agent.choice_request`'s Task 1, independently re-verified against live
    ///     `matrix-rust-sdk` source) to be the raw `m.replace` edit event, replacement fields nested
    ///     under `m.new_content` — this parser unwraps that directly, no dual-shape handling needed.
    init(body: String, parsingFrom originalJSON: String?, latestEditJSON: String?) {
        self.body = body
        let fields = Self.parseFields(from: latestEditJSON) ?? Self.parseFields(from: originalJSON)
        taskID = fields?.taskID ?? ""
        title = fields?.title ?? ""
        isResolved = fields?.status == "done"
        steps = fields?.steps ?? []
    }
    
    private struct Fields: Decodable {
        let taskID: String
        let title: String
        let status: String
        let steps: [CanvasStep]?
        
        enum CodingKeys: String, CodingKey {
            case taskID = "task_id"
            case title
            case status
            case steps
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            taskID = try container.decode(String.self, forKey: .taskID)
            title = try container.decode(String.self, forKey: .title)
            status = try container.decode(String.self, forKey: .status)
            steps = try? container.decodeIfPresent([CanvasStep].self, forKey: .steps)
        }
    }
    
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

Note: `Fields.steps` uses `try? container.decodeIfPresent(...)` (not plain `decodeIfPresent`) so that a *malformed* entry inside `steps` (present but structurally invalid, e.g. missing `label`) is caught and treated the same as a *missing* `steps` key — both fall back to `nil` → `[]` — while `taskID`/`title`/`status` remain required and independently decoded, matching `AgentChoiceRequestRoomTimelineItemContent`'s established fix for this exact class of bug (a missing/malformed one field must not silently discard the other, unrelated fields).

- [ ] **Step 4: Run tests to verify they pass**

Run over SSH on the Mac: `xcodebuild test -project ElementX.xcodeproj -scheme UnitTests -destination 'platform=iOS Simulator,id=<current simulator id>' -only-testing:UnitTests/AgentCanvasStepsRoomTimelineItemContentTests`
Expected: PASS, all 7 tests. Real console output required.

- [ ] **Step 5: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentCanvasStepsRoomTimelineItemContent.swift \
        UnitTests/Sources/AgentCanvasStepsRoomTimelineItemContentTests.swift
git commit -m "Add AgentCanvasStepsRoomTimelineItemContent"
```

---

## Task 2: `AgentCanvasStepsRoomTimelineItem` and content-type registration

**Files:**
- Create: `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentCanvasStepsRoomTimelineItem.swift`
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/EventBasedMessageTimelineItemProtocol.swift`
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/EventBasedTimelineItemProtocol.swift`
- Modify: `ElementX/Sources/Screens/Timeline/View/Replies/TimelineReplyView.swift`
- Modify: `ElementX/Sources/Screens/Timeline/View/Threads/TimelineThreadSummaryView.swift`

**Interfaces:**
- Consumes: `AgentCanvasStepsRoomTimelineItemContent` (Task 1).
- Produces: `AgentCanvasStepsRoomTimelineItem: EventBasedMessageTimelineItemProtocol, Equatable`; `EventBasedMessageTimelineItemContentType.canvasSteps(AgentCanvasStepsRoomTimelineItemContent)`.

This task has no test of its own — verified by the whole-scheme build compiling (an exhaustive switch you forget is a compile error).

- [ ] **Step 1: Create the timeline item**

Create `ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentCanvasStepsRoomTimelineItem.swift`:

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct AgentCanvasStepsRoomTimelineItem: EventBasedMessageTimelineItemProtocol, Equatable {
    let id: TimelineItemIdentifier
    let timestamp: Date
    let isOutgoing: Bool
    let isEditable: Bool
    let canBeRepliedTo: Bool
    
    let sender: TimelineItemSender
    
    let content: AgentCanvasStepsRoomTimelineItemContent
    
    var properties = RoomTimelineItemProperties()
    
    var body: String {
        content.body
    }
    
    var contentType: EventBasedMessageTimelineItemContentType {
        .canvasSteps(content)
    }
}
```

- [ ] **Step 2: Register the new case and its three switches**

In `ElementX/Sources/Services/Timeline/TimelineItems/EventBasedMessageTimelineItemProtocol.swift`, add the case to `EventBasedMessageTimelineItemContentType`:

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
    case canvasSteps(AgentCanvasStepsRoomTimelineItemContent)
}
```

Then add `.canvasSteps` alongside `.agentTurn, .choiceRequest` in each of the three switches:

```swift
nonisolated extension EventBasedMessageTimelineItemProtocol {
    var supportsMediaCaption: Bool {
        switch contentType {
        case .audio, .file, .image, .video:
            true
        case .emote, .notice, .text, .location, .voice, .agentTurn, .choiceRequest, .canvasSteps:
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
        case .emote, .notice, .text, .location, .voice, .agentTurn, .choiceRequest, .canvasSteps:
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
        case .emote, .notice, .text, .location, .voice, .agentTurn, .choiceRequest, .canvasSteps:
            nil
        }
    }
}
```

- [ ] **Step 3: Register in `isCopyable`**

In `ElementX/Sources/Services/Timeline/TimelineItems/EventBasedTimelineItemProtocol.swift`:

```swift
    var isCopyable: Bool {
        guard let messageBasedItem = self as? EventBasedMessageTimelineItemProtocol else {
            return false
        }
        
        switch messageBasedItem.contentType {
        case .audio, .file, .image, .video, .location, .voice:
            return false
        case .text, .emote, .notice, .agentTurn, .choiceRequest, .canvasSteps:
            return true
        }
    }
```

- [ ] **Step 4: Register the reply preview**

In `ElementX/Sources/Screens/Timeline/View/Replies/TimelineReplyView.swift`, find the existing `case .choiceRequest(let content):` case (added by the prior plan) and add a case right after it, matching that block's exact shape — read the file directly before writing this, since the surrounding `ReplyView(...)` call's exact parameter list must match:

```swift
                    case .choiceRequest(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.question.isEmpty ? content.body : content.question,
                                  formattedBody: nil)
                    case .canvasSteps(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.title.isEmpty ? content.body : content.title,
                                  formattedBody: nil)
```

- [ ] **Step 5: Register the thread summary**

In `ElementX/Sources/Screens/Timeline/View/Threads/TimelineThreadSummaryView.swift`, find the existing `case .choiceRequest(let content):` case and add a case right after it, matching that block's exact shape (read the file first — the exact `ThreadView(...)` parameter list must match):

```swift
                case .choiceRequest(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.question.isEmpty ? content.body : content.question,
                               numberOfReplies: numberOfReplies)
                case .canvasSteps(let content):
                    ThreadView(senderID: senderID,
                               sender: sender,
                               plainBody: content.title.isEmpty ? content.body : content.title,
                               numberOfReplies: numberOfReplies)
```

- [ ] **Step 6: Build the whole scheme**

Run over SSH on the Mac: `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>'`
Expected: `** BUILD SUCCEEDED **`. If it fails on an exhaustive switch not listed above, fix it and note the extra file in your report.

- [ ] **Step 7: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/Items/Messages/AgentCanvasStepsRoomTimelineItem.swift \
        ElementX/Sources/Services/Timeline/TimelineItems/EventBasedMessageTimelineItemProtocol.swift \
        ElementX/Sources/Services/Timeline/TimelineItems/EventBasedTimelineItemProtocol.swift \
        ElementX/Sources/Screens/Timeline/View/Replies/TimelineReplyView.swift \
        ElementX/Sources/Screens/Timeline/View/Threads/TimelineThreadSummaryView.swift
git commit -m "Register AgentCanvasStepsRoomTimelineItem's content type across exhaustive switches"
```

---

## Task 3: `RoomTimelineItemViewState`/`RoomTimelineItemType` registration

**Files:**
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemViewState.swift`

**Interfaces:**
- Consumes: `AgentCanvasStepsRoomTimelineItem` (Task 2).
- Produces: `RoomTimelineItemType.canvasSteps(AgentCanvasStepsRoomTimelineItem)`.

No test of its own — verified by the build.

- [ ] **Step 1: Add the case and its three switch sites**

In `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemViewState.swift`, add to `RoomTimelineItemType` right after the (already-registered, by the prior plan) `case choiceRequest(AgentChoiceRequestRoomTimelineItem)`:

```swift
    case choiceRequest(AgentChoiceRequestRoomTimelineItem)
    case canvasSteps(AgentCanvasStepsRoomTimelineItem)
    case poll(PollRoomTimelineItem)
```

Add to `init(item:)`'s dispatch, right after the `AgentChoiceRequestRoomTimelineItem` case:

```swift
        case let item as AgentChoiceRequestRoomTimelineItem:
            self = .choiceRequest(item)
        case let item as AgentCanvasStepsRoomTimelineItem:
            self = .canvasSteps(item)
        case let item as PollRoomTimelineItem:
            self = .poll(item)
```

Add to the `id` switch's pattern-matching case list, right after `.choiceRequest(let item as RoomTimelineItemProtocol),`:

```swift
             .choiceRequest(let item as RoomTimelineItemProtocol),
             .canvasSteps(let item as RoomTimelineItemProtocol),
             .poll(let item as RoomTimelineItemProtocol),
```

Add to the `timestamp` switch, right after `case .choiceRequest(let item): return item.timestamp`:

```swift
        case .choiceRequest(let item):
            return item.timestamp
        case .canvasSteps(let item):
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
git commit -m "Register AgentCanvasStepsRoomTimelineItem in RoomTimelineItemViewState"
```

---

## Task 4: `RoomTimelineItemFactory` interception and mock fixture

**Files:**
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemFactory.swift`
- Modify: `ElementX/Sources/Mocks/SDK/EventTimelineItem.swift`

**Interfaces:**
- Consumes: `AgentCanvasStepsRoomTimelineItem`/`AgentCanvasStepsRoomTimelineItemContent` (Tasks 1-2).
- Produces: `EventTimelineItem.mockCanvasSteps(sender:body:taskID:title:status:steps:originalJSON:) -> EventTimelineItem`.

No test of its own — exercised by Task 5's `TestablePreview` snapshot tests.

- [ ] **Step 1: Extend the factory's `.other` interception to a third msgtype**

In `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemFactory.swift`, find the `.other(let msgtype, let body)` case (already a `switch msgtype { ... }` after the prior plan added `io.element.agent.choice_request`) and add one more case:

```swift
        case .other(let msgtype, let body):
            switch msgtype {
            case AgentTurnRoomTimelineItemContent.msgType:
                return buildAgentTurnTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, body, isOutgoing)
            case AgentChoiceRequestRoomTimelineItemContent.msgType:
                return buildChoiceRequestTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, body, isOutgoing)
            case AgentCanvasStepsRoomTimelineItemContent.msgType:
                return buildCanvasStepsTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, body, isOutgoing)
            default:
                return nil
            }
```

- [ ] **Step 2: Add the builder function**

Add a new private function right after `buildChoiceRequestTimelineItem`:

```swift
    private func buildCanvasStepsTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                              _ messageLikeContent: MsgLikeContent,
                                              _ messageContent: MessageContent,
                                              _ body: String,
                                              _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        AgentCanvasStepsRoomTimelineItem(id: eventItemProxy.id,
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

In `ElementX/Sources/Mocks/SDK/EventTimelineItem.swift`, add right after `mockChoiceRequest`:

```swift
    static func mockCanvasSteps(sender: String = "",
                                body: String = "Task: Refactor auth module",
                                taskID: String = "task-1234",
                                title: String = "Refactor auth module",
                                status: String = "in_progress",
                                steps: [(id: String, label: String, status: String)] = [
                                    ("step1", "Read existing code", "done"),
                                    ("step2", "Wait for approval", "in_progress"),
                                    ("step3", "Run tests", "pending")
                                ],
                                originalJSON: String? = nil) -> EventTimelineItem {
        let messageType = MessageType.other(msgtype: AgentCanvasStepsRoomTimelineItemContent.msgType, body: body)
        
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        
        let stepsJSONArray = steps.map { "{\"id\":\"\($0.id)\",\"label\":\"\($0.label)\",\"status\":\"\($0.status)\"}" }.joined(separator: ",")
        let defaultOriginalJSON = originalJSON ?? """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"\(body)","task_id":"\(taskID)","title":"\(title)",\
        "status":"\(status)","steps":[\(stepsJSONArray)]}}
        """
        
        return .init(configuration: .init(sender: sender, content: content, originalJSON: defaultOriginalJSON))
    }
```

- [ ] **Step 4: Build the whole scheme**

Run over SSH on the Mac: `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>'`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemFactory.swift \
        ElementX/Sources/Mocks/SDK/EventTimelineItem.swift
git commit -m "Intercept io.element.agent.canvas.steps in RoomTimelineItemFactory"
```

---

## Task 5: `AgentCanvasStepsRoomTimelineView` (minimal inline card)

**Files:**
- Create: `ElementX/Sources/Screens/Timeline/View/TimelineItemViews/AgentCanvasStepsRoomTimelineView.swift`
- Modify: `ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemView.swift`

**Interfaces:**
- Consumes: `AgentCanvasStepsRoomTimelineItem` (Task 2).
- Produces: `AgentCanvasStepsRoomTimelineView: View`.

This is a purely display-only card (unlike `io.element.agent.choice_request`'s card, it sends nothing — tapping it is Task 6/7's banner+navigation job, not this card's). Covered by `TestablePreview`-generated snapshot/accessibility tests, no isolated unit test.

- [ ] **Step 1: Create the view**

Create `ElementX/Sources/Screens/Timeline/View/TimelineItemViews/AgentCanvasStepsRoomTimelineView.swift`:

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

struct AgentCanvasStepsRoomTimelineView: View {
    let timelineItem: AgentCanvasStepsRoomTimelineItem
    
    private var content: AgentCanvasStepsRoomTimelineItemContent {
        timelineItem.content
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            HStack(spacing: 4) {
                CompoundIcon(\.checkList, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundColor(.compound.iconSecondary)
                Text(content.title.isEmpty ? content.body : content.title)
                    .font(.compound.bodyMD)
                    .foregroundColor(.compound.textPrimary)
            }
        }
    }
}

struct AgentCanvasStepsRoomTimelineView_Previews: PreviewProvider, TestablePreview {
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
        AgentCanvasStepsRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                             timestamp: .mock,
                                                             isOutgoing: false,
                                                             isEditable: false,
                                                             canBeRepliedTo: true,
                                                             sender: .init(id: "@agent:example.com"),
                                                             content: .init(body: "Task: Refactor auth module",
                                                                            taskID: "task-1234",
                                                                            title: "Refactor auth module",
                                                                            isResolved: false,
                                                                            steps: [CanvasStep(id: "s1", label: "Read existing code", status: .done),
                                                                                   CanvasStep(id: "s2", label: "Wait for approval", status: .inProgress)])))
        
        AgentCanvasStepsRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                             timestamp: .mock,
                                                             isOutgoing: false,
                                                             isEditable: false,
                                                             canBeRepliedTo: true,
                                                             sender: .init(id: "@agent:example.com"),
                                                             content: .init(body: "Task: Refactor auth module",
                                                                            taskID: "task-1234",
                                                                            title: "Refactor auth module",
                                                                            isResolved: true,
                                                                            steps: [CanvasStep(id: "s1", label: "Read existing code", status: .done),
                                                                                   CanvasStep(id: "s2", label: "Run tests", status: .done)])))
    }
}
```

Note: `CompoundIcon(\.checkList, ...)` — verify `checkList` exists in the real Compound icon set on the Mac before using it (`grep -n 'public let checkList' <path-to-CompoundIcons.swift-on-the-Mac>`, same file this session already located at `~/Library/Developer/Xcode/DerivedData/ElementX-*/SourcePackages/checkouts/compound-design-tokens/assets/ios/swift/CompoundIcons.swift`). If it doesn't exist, use `\.info` instead (confirmed present, used elsewhere in `AgentTurnRoomTimelineView.swift:99`) — do not guess an icon name without checking.

- [ ] **Step 2: Wire the dispatch in `RoomTimelineItemView.swift`**

Find the existing `case .choiceRequest(let item): AgentChoiceRequestRoomTimelineView(timelineItem: item)` and add a case right after it:

```swift
        case .choiceRequest(let item):
            AgentChoiceRequestRoomTimelineView(timelineItem: item)
        case .canvasSteps(let item):
            AgentCanvasStepsRoomTimelineView(timelineItem: item)
        case .poll(let item):
            PollRoomTimelineView(timelineItem: item)
```

- [ ] **Step 3: Regenerate Sourcery-derived test files**

Run on the Mac: `sourcery --config Tools/Sourcery/PreviewTestsConfig.yml && sourcery --config Tools/Sourcery/TestablePreviewsDictionary.yml && sourcery --config Tools/Sourcery/AccessibilityTests.yml`
Expected: new generated test functions for `AgentCanvasStepsRoomTimelineView_Previews`.

- [ ] **Step 4: Build and run the generated snapshot test**

Run: `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>'`
Expected: `** BUILD SUCCEEDED **`.

Toggle `RECORD_FAILURES` to `enabled: true` in `PreviewTests/SupportingFiles/PreviewTests.xctestplan`, run `xcodebuild test -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>' -only-testing:'PreviewTests/PreviewTests/agentCanvasStepsRoomTimelineView()'` (adjust to whatever Step 3 generated) to record both preview states, then toggle `RECORD_FAILURES` back to `false` and `git checkout --` that file. Re-run once more without recording to confirm stability.
Expected: PASS.

- [ ] **Step 5: Verify pbxproj registration**

Run `/opt/homebrew/bin/xcodegen` on the Mac after your `git pull`, confirm `grep -c 'AgentCanvasStepsRoomTimelineView' ElementX.xcodeproj/project.pbxproj` is nonzero, and pull any pbxproj change back to Linux and commit it.

- [ ] **Step 6: Commit**

```bash
git add ElementX/Sources/Screens/Timeline/View/TimelineItemViews/AgentCanvasStepsRoomTimelineView.swift \
        ElementX/Sources/Services/Timeline/TimelineItems/RoomTimelineItemView.swift \
        PreviewTests/Sources/GeneratedPreviewTests.swift \
        ElementX/Sources/Other/TestablePreview/TestablePreviewsDictionary.swift \
        AccessibilityTests/Sources/GeneratedAccessibilityTests.swift \
        PreviewTests/Sources/__Snapshots__/PreviewTests/agentCanvasStepsRoomTimelineView.*
git commit -m "Add AgentCanvasStepsRoomTimelineView minimal inline card"
```

---

## Task 6: Active-task banner signal and `CanvasTaskBannerView`

**Files:**
- Modify: `ElementX/Sources/Screens/Timeline/TimelineModels.swift`
- Modify: `ElementX/Sources/Screens/Timeline/TimelineViewModel.swift`
- Create: `ElementX/Sources/Screens/RoomScreen/View/CanvasTaskBannerView.swift`
- Modify: `ElementX/Sources/Screens/RoomScreen/View/RoomScreen.swift`
- Modify: `ElementX/Resources/Localizations/en.lproj/Untranslated.strings`

**Interfaces:**
- Consumes: `AgentCanvasStepsRoomTimelineItem`/`RoomTimelineItemType.canvasSteps` (Tasks 2-3), `TimelineControllerProtocol.timelineItems: [RoomTimelineItemProtocol]` (existing).
- Produces: `TimelineViewState.activeCanvasTask: (taskID: String, title: String)?`; `TimelineViewModelAction.presentCanvasSteps(taskID: String)`; `CanvasTaskBannerView: View`.

This task's data derivation has a unit test; the banner view itself is covered by manual verification in Task 7 once the full navigation flow exists end-to-end (a banner with nothing to navigate to isn't independently meaningful to snapshot-test in isolation).

- [ ] **Step 1: Add the strings**

Add to `ElementX/Resources/Localizations/en.lproj/Untranslated.strings`:

```
"screen_room_timeline_canvas_task_banner_title" = "Task in progress";
"screen_room_timeline_canvas_task_banner_action" = "View progress";
```

Run `swiftgen config run --config Tools/SwiftGen/swiftgen-config.yml` on the Mac; confirm `UntranslatedL10n.screenRoomTimelineCanvasTaskBannerTitle`/`UntranslatedL10n.screenRoomTimelineCanvasTaskBannerAction` appear in `ElementX/Sources/Generated/Strings+Untranslated.swift`.

- [ ] **Step 2: Add `activeCanvasTask` to `TimelineViewState` and compute it**

In `ElementX/Sources/Screens/Timeline/TimelineModels.swift`, add to `TimelineViewState` right after `pinnedEventIDs`:

```swift
    /// The Matrix event ID and title of the most recently active (unresolved) `io.element.agent.canvas.steps`
    /// task in this timeline, if any. Drives `CanvasTaskBannerView`'s visibility in `RoomScreen`.
    var activeCanvasTask: (eventID: String, taskID: String, title: String)?
```

In `ElementX/Sources/Screens/Timeline/TimelineViewModel.swift`, find `buildTimelineViews(timelineItems:isSwitchingTimelines:)` (the function that already iterates every timeline item whenever the timeline updates) and add, right after its existing body (before the function returns, i.e. as its last statement — read the function's current full body first to place this correctly relative to existing code, since only its start was quoted in this plan's research):

```swift
        updateActiveCanvasTask(timelineItems: timelineItems)
```

Then add the new function near `buildTimelineViews`:

```swift
    private func updateActiveCanvasTask(timelineItems: [RoomTimelineItemProtocol]) {
        let unresolvedCanvasItem = timelineItems.reversed().first { item in
            guard let canvasItem = item as? AgentCanvasStepsRoomTimelineItem else { return false }
            return !canvasItem.content.isResolved
        } as? AgentCanvasStepsRoomTimelineItem
        
        guard let unresolvedCanvasItem, let eventID = unresolvedCanvasItem.id.eventID else {
            state.activeCanvasTask = nil
            return
        }
        
        state.activeCanvasTask = (eventID: eventID, taskID: unresolvedCanvasItem.content.taskID, title: unresolvedCanvasItem.content.title)
    }
```

`timelineItems.reversed().first { ... }` picks the most recent (last-in-timeline-order) unresolved task, matching this plan's V1 "at most one active banner, most recent wins" decision.

Add a new case to `TimelineViewModelAction` (`TimelineModels.swift:14-36`), right after `case displayThread(itemID: TimelineItemIdentifier)`:

```swift
    case displayThread(itemID: TimelineItemIdentifier)
    case presentCanvasSteps(eventID: String, taskID: String)
```

Add a new case to `TimelineViewAction` (`TimelineModels.swift:50-92`), right after `case displayThread(itemID: TimelineItemIdentifier)`:

```swift
    case displayThread(itemID: TimelineItemIdentifier)
    case tappedCanvasTaskBanner
```

In `TimelineViewModel.swift`'s `process(viewAction:)`, find `case .displayThread(let itemID): actionsSubject.send(.displayThread(itemID: itemID))` and add a case right after it:

```swift
        case .displayThread(let itemID):
            actionsSubject.send(.displayThread(itemID: itemID))
        case .tappedCanvasTaskBanner:
            guard let activeCanvasTask = state.activeCanvasTask else { return }
            actionsSubject.send(.presentCanvasSteps(eventID: activeCanvasTask.eventID, taskID: activeCanvasTask.taskID))
```

- [ ] **Step 3: Create `CanvasTaskBannerView`**

Create `ElementX/Sources/Screens/RoomScreen/View/CanvasTaskBannerView.swift`, modeled on `PinnedItemsBannerView`'s shape — read that file first to match its exact banner container styling/padding before writing this, since this plan's own research didn't capture its full body:

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

struct CanvasTaskBannerView: View {
    let title: String
    let onMainButtonTap: () -> Void
    
    var body: some View {
        Button(action: onMainButtonTap) {
            HStack(spacing: 8) {
                CompoundIcon(\.info, size: .small, relativeTo: .compound.bodyMD)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title.isEmpty ? UntranslatedL10n.screenRoomTimelineCanvasTaskBannerTitle : title)
                        .font(.compound.bodySMSemibold)
                        .foregroundColor(.compound.textPrimary)
                    Text(UntranslatedL10n.screenRoomTimelineCanvasTaskBannerAction)
                        .font(.compound.bodyXS)
                        .foregroundColor(.compound.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.compound.bgSubtlePrimary)
        }
        .buttonStyle(.plain)
    }
}

struct CanvasTaskBannerView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        CanvasTaskBannerView(title: "Refactor auth module") { }
    }
}
```

- [ ] **Step 4: Wire the banner into `RoomScreen`'s banner stack**

In `ElementX/Sources/Screens/RoomScreen/View/RoomScreen.swift`, read the existing `.topBanners([...])` call and its `pinnedItemsBanner`/`liveLocationBanner` computed properties first, to match their exact structure. Add a new `TopBannerItem` to the first `TopBannerLayer`'s `verticalBanners` array:

```swift
                TopBannerLayer(verticalBanners: [
                    TopBannerItem(pinnedItemsBanner, isVisible: context.viewState.shouldShowPinnedEventsBanner && !isVoiceOverEnabled),
                    TopBannerItem(liveLocationBanner, isVisible: context.viewState.isSharingLiveLocation && !isVoiceOverEnabled),
                    TopBannerItem(canvasTaskBanner, isVisible: timelineContext.viewState.activeCanvasTask != nil)
```

Add a new computed property alongside `pinnedItemsBanner`/`liveLocationBanner`:

```swift
    private var canvasTaskBanner: some View {
        CanvasTaskBannerView(title: timelineContext.viewState.activeCanvasTask?.title ?? "") {
            timelineContext.send(viewAction: .tappedCanvasTaskBanner)
        }
    }
```

Note: this banner reads `timelineContext` (the `TimelineViewModel.Context` already held by `RoomScreen` as `@ObservedObject private var timelineContext`, confirmed at `RoomScreen.swift:16`) directly — it does not need `!isVoiceOverEnabled` gating like the other two banners unless you determine during implementation that VoiceOver users need the same alternate-rendering treatment those banners get (`RoomScreen.swift:85-94`'s `if ... isVoiceOverEnabled` block) for this new banner too; if so, add it there following that exact pattern rather than inventing a new one.

- [ ] **Step 5: Build the whole scheme**

Run over SSH on the Mac: `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>'`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Write and run a unit test for `updateActiveCanvasTask`**

Add to `UnitTests/Sources/TimelineViewModelTests.swift` (an existing test file — find it and match its existing setup/mock conventions before adding this test, since this plan's research didn't capture its current structure):

```swift
    @Test
    func mostRecentUnresolvedCanvasTaskDrivesActiveCanvasTask() async throws {
        // Build a mock timeline containing one resolved and one unresolved canvas-steps item,
        // confirm activeCanvasTask reflects only the unresolved (most recent) one.
        // Exact mock/harness setup to match this file's existing test patterns.
    }
```

Run: `xcodebuild test -project ElementX.xcodeproj -scheme UnitTests -destination 'platform=iOS Simulator,id=<current simulator id>' -only-testing:UnitTests/TimelineViewModelTests/mostRecentUnresolvedCanvasTaskDrivesActiveCanvasTask`
Expected: PASS. If `TimelineViewModelTests.swift` doesn't exist or has a substantially different harness than assumed, adapt the test to fit its actual conventions rather than forcing this exact shape — the requirement is one real test proving `updateActiveCanvasTask` picks the most recent unresolved item, not this literal code.

- [ ] **Step 7: Commit**

```bash
git add ElementX/Sources/Screens/Timeline/TimelineModels.swift \
        ElementX/Sources/Screens/Timeline/TimelineViewModel.swift \
        ElementX/Sources/Screens/RoomScreen/View/CanvasTaskBannerView.swift \
        ElementX/Sources/Screens/RoomScreen/View/RoomScreen.swift \
        ElementX/Resources/Localizations/en.lproj/Untranslated.strings \
        ElementX/Sources/Generated/Strings+Untranslated.swift \
        UnitTests/Sources/TimelineViewModelTests.swift
git commit -m "Add active-canvas-task banner signal and CanvasTaskBannerView"
```

---

## Task 7: `CanvasStepsScreen` and navigation wiring

**Files:**
- Create: `ElementX/Sources/Screens/CanvasStepsScreen/CanvasStepsScreenModels.swift`
- Create: `ElementX/Sources/Screens/CanvasStepsScreen/CanvasStepsScreenViewModelProtocol.swift`
- Create: `ElementX/Sources/Screens/CanvasStepsScreen/CanvasStepsScreenViewModel.swift`
- Create: `ElementX/Sources/Screens/CanvasStepsScreen/View/CanvasStepsScreen.swift`
- Create: `ElementX/Sources/Screens/CanvasStepsScreen/CanvasStepsScreenCoordinator.swift`
- Modify: `ElementX/Sources/Screens/RoomScreen/RoomScreenCoordinator.swift`
- Modify: `ElementX/Sources/FlowCoordinators/RoomFlowCoordinatorStateMachine.swift`
- Modify: `ElementX/Sources/FlowCoordinators/RoomFlowCoordinator.swift`

**Interfaces:**
- Consumes: `TimelineViewModelAction.presentCanvasSteps(eventID:taskID:)` (Task 6), `AgentCanvasStepsRoomTimelineItemContent` (Task 1), `TimelineControllerProtocol.timelineItems` (existing).
- Produces: `RoomScreenCoordinatorAction.presentCanvasSteps(eventID: String, taskID: String)`; `CanvasStepsScreenCoordinatorParameters`; a pushed screen showing the full step list for one task.

No isolated unit test for the navigation plumbing (verified by the build and by manual on-device verification below); `CanvasStepsScreenViewModel`'s own step-list-rendering logic is simple enough to be covered entirely by the screen's `TestablePreview` snapshot test.

- [ ] **Step 1: Create the screen's Models/ViewModelProtocol/ViewModel/View**

Follow `Tools/Scripts/Templates/SimpleScreenExample/`'s file shape (read `TemplateScreenModels.swift`/`TemplateScreenViewModelProtocol.swift`/`TemplateScreenViewModel.swift`/`View/TemplateScreen.swift` directly before writing these four files, to match this codebase's exact `StateStoreViewModelV2` conventions — this plan's own research read the *Coordinator* template in full but not these four).

`CanvasStepsScreenModels.swift` needs: a `CanvasStepsScreenViewState: BindableState` holding `title: String` and `steps: [CanvasStep]` (from Task 1); a `CanvasStepsScreenViewAction` with at least `case close`; a `CanvasStepsScreenViewModelAction` with at least `case dismiss`.

`CanvasStepsScreenViewModel` is initialized with the already-parsed `title`/`steps` directly (no live re-subscription needed for V1 — the screen renders a one-time snapshot of whatever `AgentCanvasStepsRoomTimelineItemContent` the banner-tap handler already had; if the task updates again while the screen is open, the user re-opens it via the banner to see the refresh, which is an acceptable V1 limitation given this plan's read-only scope).

`CanvasStepsScreen`'s view renders `context.viewState.title` as a nav title and `context.viewState.steps` as a simple list, each row showing the step's label and a status icon (`\.check`/`\.time`/`\.circle` for done/in-progress/pending — reuse `AgentTurnRoomTimelineView.swift:87-101`'s `statusIcon(for:)` shape as the pattern, adapted for `CanvasStep.Status` instead of `ToolCallSummary.Status`).

- [ ] **Step 2: Create the Coordinator**

Create `ElementX/Sources/Screens/CanvasStepsScreen/CanvasStepsScreenCoordinator.swift`, following `Tools/Scripts/Templates/SimpleScreenExample/ElementX/TemplateScreenCoordinator.swift`'s exact shape:

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct CanvasStepsScreenCoordinatorParameters {
    let title: String
    let steps: [CanvasStep]
}

enum CanvasStepsScreenCoordinatorAction {
    case dismiss
}

final class CanvasStepsScreenCoordinator: CoordinatorProtocol {
    private let parameters: CanvasStepsScreenCoordinatorParameters
    private let viewModel: CanvasStepsScreenViewModelProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<CanvasStepsScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CanvasStepsScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: CanvasStepsScreenCoordinatorParameters) {
        self.parameters = parameters
        viewModel = CanvasStepsScreenViewModel(title: parameters.title, steps: parameters.steps)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss:
                actionsSubject.send(.dismiss)
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(CanvasStepsScreen(context: viewModel.context))
    }
}
```

(This assumes `CanvasStepsScreenViewModel`'s initializer signature from Step 1 is `init(title: String, steps: [CanvasStep])` — keep it consistent with whatever you actually wrote there.)

- [ ] **Step 3: Add `RoomScreenCoordinatorAction.presentCanvasSteps` and bridge it**

In `ElementX/Sources/Screens/RoomScreen/RoomScreenCoordinator.swift`, add a case to `RoomScreenCoordinatorAction` (`RoomScreenCoordinator.swift:35-54`), right after `case presentThread(...)`:

```swift
    case presentThread(threadRootEventID: String, focussedEventID: String?)
    case presentCanvasSteps(eventID: String, taskID: String)
```

Find where `timelineViewModel.actionsPublisher` is subscribed (the `switch action` block containing `case .displayThread(let itemID): ...`) and add a case right after it:

```swift
                case .displayThread(let itemID):
                    // existing handling, do not modify — read the real surrounding code first
                    break
                case .presentCanvasSteps(let eventID, let taskID):
                    actionsSubject.send(.presentCanvasSteps(eventID: eventID, taskID: taskID))
```

(The `.displayThread` line above is a placeholder to show *where* to insert your new case, not a real diff — copy the actual existing `.displayThread` handling verbatim from the file and add `.presentCanvasSteps` immediately after it, do not replace or alter the existing case.)

- [ ] **Step 4: Add the state machine state/event and route mapping**

In `ElementX/Sources/FlowCoordinators/RoomFlowCoordinatorStateMachine.swift`, add to `State` (`RoomFlowCoordinatorStateMachine.swift:58-98`), right after `case pinnedEventsTimeline(previousState: State)`:

```swift
        case pinnedEventsTimeline(previousState: State)
        case canvasSteps(eventID: String, taskID: String, previousState: State)
```

Add to `Event` (`RoomFlowCoordinatorStateMachine.swift:107-`), right after `case presentThreadList`/`case dismissThreadList`:

```swift
        case presentThreadList
        case dismissThreadList
        
        case presentCanvasSteps(eventID: String, taskID: String)
        case dismissCanvasSteps
```

Add the route mapping (find the `addRouteMapping` block containing `case (.room, .presentThreadList): return .threadList` and the corresponding dismiss mapping, and add analogous cases right there):

```swift
            case (.room, .presentCanvasSteps(let eventID, let taskID)):
                return .canvasSteps(eventID: eventID, taskID: taskID, previousState: fromState)
                
            case (.canvasSteps(_, _, let previousState), .dismissCanvasSteps):
                return previousState
```

- [ ] **Step 5: Wire the state transition side effect and the coordinator-action bridge**

In `ElementX/Sources/FlowCoordinators/RoomFlowCoordinator.swift`, find the big `(fromState, event, toState)` switch (containing `case (.room, .presentThreadList, .threadList): Task { await self.presentThreadList(animated: animated) }`) and add a case:

```swift
            case (.room, .presentCanvasSteps, .canvasSteps(let eventID, let taskID, _)):
                Task { await self.presentCanvasSteps(eventID: eventID, taskID: taskID, animated: animated) }
```

Add the `presentCanvasSteps` function, modeled on `presentThreadList` (`RoomFlowCoordinator.swift:755-771`) — it needs to look up the already-loaded timeline item by event ID (via `timelineController.timelineItems`, the same source Task 6's `updateActiveCanvasTask` reads) to get its `title`/`steps`, since this plan's V1 scope (per Task 7 Step 1) doesn't build a live re-fetch:

```swift
    private func presentCanvasSteps(eventID: String, taskID: String, animated: Bool) async {
        guard let canvasItem = timelineController.timelineItems.first(where: { $0.id.eventID == eventID }) as? AgentCanvasStepsRoomTimelineItem else {
            MXLog.error("Failed presenting canvas steps: item not found for eventID \(eventID)")
            stateMachine.tryEvent(.dismissCanvasSteps)
            return
        }
        
        let coordinator = CanvasStepsScreenCoordinator(parameters: .init(title: canvasItem.content.title, steps: canvasItem.content.steps))
        
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss:
                stateMachine.tryEvent(.dismissCanvasSteps)
            }
        }.store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator, animated: animated) { [weak self] in
            guard let self else { return }
            stateMachine.tryEvent(.dismissCanvasSteps)
        }
    }
```

Find where `RoomScreenCoordinatorAction` cases are bridged into `stateMachine.tryEvent(...)` calls (containing `case .presentThreadList: stateMachine.tryEvent(.presentThreadList, userInfo: EventUserInfo(animated: animated))`) and add:

```swift
                case .presentCanvasSteps(let eventID, let taskID):
                    stateMachine.tryEvent(.presentCanvasSteps(eventID: eventID, taskID: taskID), userInfo: EventUserInfo(animated: animated))
```

Note: confirm `timelineController` is actually a property already in scope on `RoomFlowCoordinator` (it's referenced by other functions like `presentThread`, so it should be) before assuming this compiles as written — if it's named differently or reached via a different path, adjust to match the real property name.

- [ ] **Step 6: Build the whole scheme**

Run over SSH on the Mac: `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>'`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Regenerate Sourcery and verify pbxproj registration**

This task creates 5 new files — run `/opt/homebrew/bin/xcodegen` on the Mac after your `git pull`, confirm all 5 are registered (`grep -c 'CanvasStepsScreen' ElementX.xcodeproj/project.pbxproj` should be nonzero and reflect multiple files), pull any pbxproj change back and commit it. If `CanvasStepsScreen.swift`'s preview needs Sourcery regeneration (it should, being a new `TestablePreview`), run the same 3 Sourcery configs as prior tasks and commit their output too.

- [ ] **Step 8: Manually verify the flow**

Build and run the app on the simulator/device. Since there's no live agent posting real canvas-steps messages yet, use the mock fixture's shape as a reference to manually construct a test message (or, if a test homeserver account with send access is available this session — check what prior tasks found — post a raw `io.element.agent.canvas.steps` event via a script) and confirm: the banner appears in `RoomScreen` when an unresolved task exists, tapping it pushes `CanvasStepsScreen` showing the right title/steps, and the back button returns to the room. If no live send capability is available (matching this session's repeated finding of no test-account access), verify as much as possible via the build succeeding and the previews rendering correctly, and report honestly which parts were and weren't interactively verified — do not claim full manual verification you didn't actually perform.

- [ ] **Step 9: Commit**

```bash
git add ElementX/Sources/Screens/CanvasStepsScreen/ \
        ElementX/Sources/Screens/RoomScreen/RoomScreenCoordinator.swift \
        ElementX/Sources/FlowCoordinators/RoomFlowCoordinatorStateMachine.swift \
        ElementX/Sources/FlowCoordinators/RoomFlowCoordinator.swift
git commit -m "Add CanvasStepsScreen and wire navigation from the canvas task banner"
```

---

## Self-Review Notes

- **Spec coverage:** every decision in `docs/superpowers/specs/2026-07-04-agent-canvas-steps-design.md` is covered — flat step list only (Tasks 1, 7), message-based not state-event-based (Tasks 1-4, reusing the proven pipeline), inline minimal card preserved for audit (Task 5), banner entry point (Task 6), pushed screen not third nav column (Task 7, confirmed no `NavigationSplitCoordinator` changes anywhere in this plan), one-active-task-at-a-time (Task 6's `updateActiveCanvasTask` picks only the most recent unresolved item), read-only canvas screen (Task 7 sends no Matrix events, only reads already-loaded timeline items).
- **Placeholder scan:** no TBD/TODO. Task 6 Step 6 and Task 7 Step 1 both explicitly instruct the implementer to read real files before finalizing exact code where this plan's own research was incomplete (`TimelineViewModelTests.swift`'s existing structure, the four template screen files, `PinnedItemsBannerView`'s exact styling) — flagged honestly as open per-file research the implementer must do, not guessed at and presented as certain. This is a deliberate, bounded exception to "no placeholders," scoped to cosmetic/structural details (test harness conventions, banner padding) that don't change the plan's architecture — every functional line of code (parsing logic, registration switches, state machine wiring, navigation flow) is complete and concrete.
- **Type consistency:** `AgentCanvasStepsRoomTimelineItemContent`, `CanvasStep`, `AgentCanvasStepsRoomTimelineItem`, `.canvasSteps` case name, `activeCanvasTask`, `CanvasStepsScreenCoordinatorParameters` are named identically everywhere referenced across all 7 tasks.
- **Verified against real code, not guessed:** `NavigationSplitCoordinator`'s genuine 2-column-only nature (`NavigationCoordinators.swift:14,386-404`), `StateEventContent`'s closed-enum nature with no custom-type escape hatch (`matrix_sdk_ffi.swift:40345-40374`, checked directly on the Mac's vendored SDK checkout), `RoomScreenViewModel` having no direct `timelineController` access while `RoomScreen.swift` already holds `timelineContext: TimelineViewModelType.Context` as a property (`RoomScreen.swift:16`) — this is what resolves the design doc's own flagged "open implementation question" about where the banner-visibility computation belongs — `TimelineControllerProtocol.timelineItems`'s existence (`TimelineControllerProtocol.swift:51`), `RoomScreenCoordinatorAction`'s real case list and `RoomFlowCoordinator`'s real `presentThreadList`/state-machine transition pattern (`RoomFlowCoordinator.swift:35-54,755-771,700-745`), `RoomFlowCoordinatorStateMachine`'s real `State`/`Event`/route-mapping shape including a `previousState`-carrying case's dismiss pattern (`RoomFlowCoordinatorStateMachine.swift:58-98,107-129,230-301`) — all read directly from the current source before writing this plan's Task 6-7 code, not inferred from the design doc alone.
