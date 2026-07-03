//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import LoremSwiftum
import MatrixRustSDK
import MatrixRustSDKMocks

nonisolated struct EventTimelineItemSDKMockConfiguration {
    var eventID: String = UUID().uuidString
    var sender = ""
    var senderProfile: ProfileDetails?
    var forwarder: String?
    var forwarderProfile: ProfileDetails?
    var isOwn = false
    var isEditable = false
    var canBeRepliedTo = false
    var content: TimelineItemContent = .msgLike(content: .init(kind: .redacted,
                                                               reactions: [],
                                                               inReplyTo: nil,
                                                               threadRoot: nil,
                                                               threadSummary: nil))
    var originalJSON: String?
}

nonisolated extension EventTimelineItem {
    init(configuration: EventTimelineItemSDKMockConfiguration) {
        let lazyProvider = LazyTimelineItemProviderSDKMock()
        lazyProvider.containsOnlyEmojisReturnValue = false
        lazyProvider.getShieldsStrictReturnValue = ShieldState.none
        lazyProvider.debugInfoReturnValue = .init(model: "", originalJson: configuration.originalJSON, latestEditJson: nil)
        self.init(isRemote: true,
                  eventOrTransactionId: .eventId(eventId: configuration.eventID),
                  sender: configuration.sender,
                  senderProfile: configuration.senderProfile ?? .pending,
                  forwarder: configuration.forwarder,
                  forwarderProfile: configuration.forwarderProfile,
                  isOwn: configuration.isOwn,
                  isEditable: configuration.isEditable,
                  content: configuration.content,
                  eventTypeRaw: nil,
                  timestamp: UInt64(Date.mock.timeIntervalSince1970 * 1000),
                  localSendState: nil,
                  localCreatedAt: nil,
                  readReceipts: [:],
                  origin: nil,
                  canBeRepliedTo: configuration.canBeRepliedTo,
                  lazyProvider: lazyProvider)
    }
    
    static var mockMessage: EventTimelineItem {
        let body = Lorem.sentences(Int.random(in: 1...5))
        let messageType = MessageType.text(content: .init(body: body, formatted: nil))
        
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        
        return .init(configuration: .init(content: content))
    }
    
    static func mockCallInvite(sender: String) -> EventTimelineItem {
        .init(configuration: .init(sender: sender, content: .callInvite))
    }
    
    static func mockAgentTurn(sender: String = "", body: String = "Final reply", originalJSON: String? = nil) -> EventTimelineItem {
        let messageType = MessageType.other(msgtype: AgentTurnRoomTimelineItemContent.msgType, body: body)
        
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        
        return .init(configuration: .init(sender: sender, content: content, originalJSON: originalJSON))
    }
    
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
}
