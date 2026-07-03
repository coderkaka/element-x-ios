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
        {"content":{"msgtype":"io.element.agent.canvas.steps","body":"* Done",
        "m.new_content":{"msgtype":"io.element.agent.canvas.steps","body":"Done","task_id":"t","title":"T","status":"done",
        "steps":[{"id":"s1","label":"L","status":"done"}]},
        "m.relates_to":{"rel_type":"m.replace","event_id":"$original"}}}
        """
        let content = AgentCanvasStepsRoomTimelineItemContent(body: "fallback", parsingFrom: original, latestEditJSON: edit)
        #expect(content.isResolved == true)
        #expect(content.steps == [CanvasStep(id: "s1", label: "L", status: .done)])
    }
}
