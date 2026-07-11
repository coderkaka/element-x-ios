//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

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
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "Task: Refactor auth module", parsingFrom: json)
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
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: json)
        #expect(content.steps == [CanvasStep(id: "s1", label: "L", status: .other("blocked"))])
    }
    
    @Test
    func missingStepsFieldFallsBackToEmpty() {
        let json = """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"fallback","task_id":"t","title":"T","status":"in_progress"}}
        """
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: json)
        #expect(content.steps.isEmpty)
        #expect(content.title == "T")
    }
    
    @Test
    func malformedStepEntryFallsBackToEmptySteps() {
        let json = """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"fallback","task_id":"t","title":"T","status":"in_progress",
        "steps":[{"id":"s1"}]}}
        """
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: json)
        #expect(content.steps.isEmpty)
        #expect(content.title == "T")
    }
    
    @Test
    func nilOriginalJSONFallsBackToEmptyDefaults() {
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: nil)
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
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: json)
        #expect(content.isResolved == false)
    }
    
    @Test
    func messageStatusDoneIsResolvedEvenBeforeAnyStateUpdate() {
        // A task that's already `"done"` in its very first message (no progress updates needed) must
        // still be recognised as resolved from the message alone — resolution only moves to the state
        // event for updates *after* the initial message.
        let json = """
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"fallback","task_id":"t","title":"T","status":"done",
        "steps":[{"id":"s1","label":"L","status":"done"}]}}
        """
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: json)
        #expect(content.isResolved == true)
    }
}

struct AgentCanvasStepsStateContentTests {
    @Test
    func parsesWellFormedDoneStateEvent() {
        let json = """
        {"type":"io.element.agent.canvas.steps","state_key":"t",
        "content":{"status":"done","steps":[{"id":"s1","label":"L","status":"done"}]}}
        """
        let content = AgentCanvasStepsStateContent(parsingFrom: json)
        #expect(content?.isResolved == true)
        #expect(content?.steps == [CanvasStep(id: "s1", label: "L", status: .done)])
    }
    
    @Test
    func parsesInProgressStateEvent() {
        let json = """
        {"type":"io.element.agent.canvas.steps","state_key":"t",
        "content":{"status":"in_progress","steps":[{"id":"s1","label":"L","status":"in_progress"}]}}
        """
        let content = AgentCanvasStepsStateContent(parsingFrom: json)
        #expect(content?.isResolved == false)
    }
    
    @Test
    func missingStepsFieldFallsBackToEmpty() {
        let json = """
        {"type":"io.element.agent.canvas.steps","state_key":"t","content":{"status":"in_progress"}}
        """
        let content = AgentCanvasStepsStateContent(parsingFrom: json)
        #expect(content?.steps.isEmpty == true)
    }
    
    @Test
    func nilRawJSONReturnsNil() {
        #expect(AgentCanvasStepsStateContent(parsingFrom: nil) == nil)
    }
    
    @Test
    func parsesTitleThreadRootAndUpdatedAtWhenPresent() {
        let json = """
        {"type":"io.element.agent.canvas.steps","state_key":"t",
        "content":{"status":"in_progress","title":"Refactor auth module",
        "thread_root_id":"$thread-root","updated_at":1783222459000,
        "steps":[{"id":"s1","label":"L","status":"done"}]}}
        """
        let content = AgentCanvasStepsStateContent(parsingFrom: json)
        #expect(content?.title == "Refactor auth module")
        #expect(content?.threadRootEventID == "$thread-root")
        #expect(content?.updatedAt == Date(timeIntervalSince1970: 1_783_222_459))
    }
    
    @Test
    func missingOptionalFieldsFallBackToNil() {
        let json = """
        {"type":"io.element.agent.canvas.steps","state_key":"t","content":{"status":"in_progress"}}
        """
        let content = AgentCanvasStepsStateContent(parsingFrom: json)
        #expect(content != nil)
        #expect(content?.title == nil)
        #expect(content?.threadRootEventID == nil)
        #expect(content?.updatedAt == nil)
    }
    
    @Test
    func updatedAtIsParsedAsMillisecondsSinceEpoch() {
        let json = """
        {"type":"io.element.agent.canvas.steps","state_key":"t",
        "content":{"status":"done","updated_at":1500}}
        """
        let content = AgentCanvasStepsStateContent(parsingFrom: json)
        #expect(content?.updatedAt == Date(timeIntervalSince1970: 1.5))
    }
    
    @Test
    func malformedOptionalFieldsDoNotFailTheWholeDecode() {
        let json = """
        {"type":"io.element.agent.canvas.steps","state_key":"t",
        "content":{"status":"done","title":42,"thread_root_id":true,"updated_at":"not-a-number"}}
        """
        let content = AgentCanvasStepsStateContent(parsingFrom: json)
        #expect(content?.isResolved == true)
        #expect(content?.title == nil)
        #expect(content?.threadRootEventID == nil)
        #expect(content?.updatedAt == nil)
    }
}
