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
    
    /// - Parameter originalJSON: the raw Matrix event JSON from `EventTimelineItemProxy.debugInfo.originalJSON`.
    ///   The Rust SDK only exposes the standard `body` field for custom msgtypes via `MessageType.other`,
    ///   so `question`/`options`/`multi_select` have to be recovered by hand from the raw event — the same
    ///   reasoning `AgentTurnRoomTimelineItemContent` documents for `tool_calls`.
    ///
    ///   `resolved_selection` is intentionally not read here: it's mutable state that lives in a
    ///   `io.element.agent.choice_request` room state event (state key = this message's event ID),
    ///   read separately via `getStateEventRaw` — see `AgentChoiceRequestRoomTimelineView`.
    init(body: String, parsingFrom originalJSON: String?) {
        self.body = body
        let fields = Self.parseFields(from: originalJSON)
        question = fields?.question ?? ""
        options = fields?.options ?? []
        multiSelect = fields?.multiSelect ?? false
        resolvedSelection = nil
    }
    
    private struct Fields: Decodable {
        let question: String
        let options: [ChoiceOption]
        let multiSelect: Bool
        
        enum CodingKeys: String, CodingKey {
            case question
            case options
            case multiSelect = "multi_select"
        }
        
        /// Custom init so a missing `options` key falls back to `[]` instead of failing the whole
        /// decode (the synthesized Decodable would throw keyNotFound, discarding `question` too).
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            question = try container.decode(String.self, forKey: .question)
            options = try container.decodeIfPresent([ChoiceOption].self, forKey: .options) ?? []
            multiSelect = try container.decode(Bool.self, forKey: .multiSelect)
        }
    }
    
    private struct EventEnvelope: Decodable {
        let content: Fields
    }
    
    private static func parseFields(from json: String?) -> Fields? {
        guard let data = json?.data(using: .utf8) else { return nil }
        guard let event = try? JSONDecoder().decode(EventEnvelope.self, from: data) else { return nil }
        return event.content
    }
}

/// The `io.element.agent.choice_request` room state event content, keyed by the choice request
/// message's event ID. Its presence/`resolvedSelection` is how the client learns a choice was made,
/// without depending on message edits.
nonisolated struct AgentChoiceRequestStateContent: Decodable {
    let resolvedSelection: [String]
    
    enum CodingKeys: String, CodingKey {
        case resolvedSelection = "resolved_selection"
    }
    
    /// - Parameter rawStateEventJSON: the full raw state event JSON string returned by
    ///   `getStateEventRaw`, i.e. `{"type": ..., "state_key": ..., "content": {"resolved_selection": [...]}, ...}`.
    init?(parsingFrom rawStateEventJSON: String?) {
        guard let data = rawStateEventJSON?.data(using: .utf8) else { return nil }
        
        struct EventEnvelope: Decodable {
            let content: AgentChoiceRequestStateContent
        }
        
        guard let event = try? JSONDecoder().decode(EventEnvelope.self, from: data) else { return nil }
        self = event.content
    }
}
