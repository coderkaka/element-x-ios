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
