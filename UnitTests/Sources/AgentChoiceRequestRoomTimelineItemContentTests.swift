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
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: json)
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
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: json)
        #expect(content.multiSelect == true)
    }
    
    @Test
    func missingOptionsFieldFallsBackToEmpty() {
        let json = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"fallback","question":"Q?","multi_select":false}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: json)
        #expect(content.options.isEmpty)
        #expect(content.question == "Q?")
    }
    
    @Test
    func malformedOptionsEntryFallsBackToEmpty() {
        let json = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"fallback","question":"Q?",
        "options":[{"id":"a"}],"multi_select":false}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: json)
        #expect(content.options.isEmpty)
    }
    
    @Test
    func nilOriginalJSONFallsBackToEmptyDefaults() {
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: nil)
        #expect(content.question.isEmpty)
        #expect(content.options.isEmpty)
        #expect(content.multiSelect == false)
        #expect(content.resolvedSelection == nil)
    }
    
    @Test
    func messageContentNeverExposesResolvedSelection() {
        // `resolvedSelection` now only ever comes from a room state event (`AgentChoiceRequestStateContent`),
        // never from the message itself — even if a (no longer supported) `resolved_selection` key were
        // present on the message, it must not leak through.
        let json = """
        {"content":{"msgtype":"io.element.agent.choice_request","body":"fallback","question":"Q?",
        "options":[{"id":"a","label":"A"}],"multi_select":false,"resolved_selection":["a"]}}
        """
        let content = AgentChoiceRequestRoomTimelineItemContent(body: "fallback", parsingFrom: json)
        #expect(content.resolvedSelection == nil)
    }
}

struct AgentChoiceRequestStateContentTests {
    @Test
    func parsesWellFormedStateEvent() {
        let json = """
        {"type":"io.element.agent.choice_request","state_key":"$original",
        "content":{"resolved_selection":["a"]}}
        """
        let content = AgentChoiceRequestStateContent(parsingFrom: json)
        #expect(content?.resolvedSelection == ["a"])
    }
    
    @Test
    func parsesMultipleResolvedIDs() {
        let json = """
        {"type":"io.element.agent.choice_request","state_key":"$original",
        "content":{"resolved_selection":["a","b"]}}
        """
        let content = AgentChoiceRequestStateContent(parsingFrom: json)
        #expect(content?.resolvedSelection == ["a", "b"])
    }
    
    @Test
    func nilRawJSONReturnsNil() {
        #expect(AgentChoiceRequestStateContent(parsingFrom: nil) == nil)
    }
    
    @Test
    func missingResolvedSelectionKeyReturnsNil() {
        let json = """
        {"type":"io.element.agent.choice_request","state_key":"$original","content":{}}
        """
        #expect(AgentChoiceRequestStateContent(parsingFrom: json) == nil)
    }
}
