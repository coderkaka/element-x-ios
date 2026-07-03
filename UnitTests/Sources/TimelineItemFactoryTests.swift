//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import MatrixRustSDK
import Testing

@MainActor
struct TimelineItemFactoryTests {
    @Test
    func callInvite() throws {
        let ownUserID = "@alice:matrix.org"
        let senderUserID = "@bob:matrix.org"
        
        let factory = RoomTimelineItemFactory(userID: ownUserID,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: ownUserID))
        
        let eventTimelineItem = EventTimelineItem.mockCallInvite(sender: senderUserID)
        
        let eventTimelineItemProxy = EventTimelineItemProxy(item: eventTimelineItem, uniqueID: .init("0"))
        
        let item = try #require(factory.buildTimelineItem(for: eventTimelineItemProxy, isDM: false) as? CallInviteRoomTimelineItem,
                                "Incorrect item type")
        
        #expect(item.isReactable == false)
        #expect(item.canBeRepliedTo == false)
        #expect(item.isEditable == false)
        #expect(item.sender == TimelineItemSender(id: senderUserID))
        #expect(item.properties.isEdited == false)
        #expect(item.properties.reactions == [])
        #expect(item.properties.deliveryStatus == nil)
    }
    
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
        
        let eventTimelineItem = EventTimelineItem.mockAgentTurn(sender: senderUserID, body: "Done reading.", originalJSON: originalJSON)
        let eventTimelineItemProxy = EventTimelineItemProxy(item: eventTimelineItem, uniqueID: .init("0"))
        
        let item = try #require(factory.buildTimelineItem(for: eventTimelineItemProxy, isDM: false) as? AgentTurnRoomTimelineItem,
                                "Incorrect item type")
        
        #expect(item.content.body == "Done reading.")
        #expect(item.content.toolCalls == [ToolCallSummary(name: "read_file", status: .done, summary: "Read Foo.swift")])
        #expect(item.sender == TimelineItemSender(id: senderUserID))
    }
    
    @Test
    func choiceRequestWithOptions() throws {
        let ownUserID = "@alice:matrix.org"
        let senderUserID = "@agent:matrix.org"
        
        let factory = RoomTimelineItemFactory(userID: ownUserID,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: ownUserID))
        
        let eventTimelineItem = EventTimelineItem.mockChoiceRequest(sender: senderUserID,
                                                                    body: "Which environment?",
                                                                    question: "Which environment should I deploy to?",
                                                                    options: [("test", "Test"), ("prod", "Production")],
                                                                    multiSelect: false)
        let eventTimelineItemProxy = EventTimelineItemProxy(item: eventTimelineItem, uniqueID: .init("0"))
        
        let item = try #require(factory.buildTimelineItem(for: eventTimelineItemProxy, isDM: false) as? AgentChoiceRequestRoomTimelineItem,
                                "Incorrect item type")
        
        #expect(item.content.body == "Which environment?")
        #expect(item.content.question == "Which environment should I deploy to?")
        #expect(item.content.options == [ChoiceOption(id: "test", label: "Test"), ChoiceOption(id: "prod", label: "Production")])
        #expect(item.content.multiSelect == false)
        #expect(item.content.resolvedSelection == nil)
        #expect(item.sender == TimelineItemSender(id: senderUserID))
    }
    
    @Test
    func choiceRequestWithResolvedSelectionFromLatestEdit() throws {
        let ownUserID = "@alice:matrix.org"
        let senderUserID = "@agent:matrix.org"
        
        let factory = RoomTimelineItemFactory(userID: ownUserID,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: ownUserID))
        
        let latestEditJSON = """
        {"content": {"question": "Which environment should I deploy to?", \
        "options": [{"id": "test", "label": "Test"}, {"id": "prod", "label": "Production"}], \
        "multi_select": false, "resolved_selection": ["prod"]}}
        """
        
        let eventTimelineItem = EventTimelineItem.mockChoiceRequest(sender: senderUserID,
                                                                    body: "Which environment?",
                                                                    question: "Which environment should I deploy to?",
                                                                    options: [("test", "Test"), ("prod", "Production")],
                                                                    multiSelect: false,
                                                                    latestEditJSON: latestEditJSON)
        let eventTimelineItemProxy = EventTimelineItemProxy(item: eventTimelineItem, uniqueID: .init("0"))
        
        let item = try #require(factory.buildTimelineItem(for: eventTimelineItemProxy, isDM: false) as? AgentChoiceRequestRoomTimelineItem,
                                "Incorrect item type")
        
        // Proves latestEditJSON is threaded all the way through the mock configuration into the built item,
        // rather than being silently dropped (it used to be hardcoded to nil in EventTimelineItemSDKMockConfiguration).
        #expect(item.content.resolvedSelection == ["prod"])
    }
    
    @Test
    func unrecognisedCustomMsgtypeIsStillDropped() {
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
}
