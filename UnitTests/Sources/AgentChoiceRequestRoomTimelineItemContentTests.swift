//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

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
