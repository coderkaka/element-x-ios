//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum AgentProjectStatus: String {
    case active, done, archived
}

nonisolated struct AgentProjectSummary: Identifiable, Equatable {
    let roomID: String
    let name: String?
    let description: String?
    let status: AgentProjectStatus
    
    var id: String {
        roomID
    }
}

nonisolated struct AgentPendingChoiceSummary: Identifiable, Equatable {
    let roomID: String
    /// The `state_key` of the choice request event — equal to the original message's event ID.
    let eventID: String
    let question: String?
    
    var id: String {
        "\(roomID)|\(eventID)"
    }
}

/// Parses the full raw state event JSON returned by `getRoomStateEventsRaw` for
/// `io.element.agent.goal` (state key is always the empty string).
///
/// Parsing is deliberately lenient: any well-formed JSON object is accepted, even one with
/// no recognisable fields, since the mere presence of a parseable goal event is what marks
/// a room as a project.
nonisolated struct AgentGoalStateEvent: Decodable {
    static let eventType = "io.element.agent.goal"
    
    let name: String?
    let description: String?
    let status: AgentProjectStatus
    
    private enum EventKeys: String, CodingKey {
        case content
    }
    
    private struct Content: Decodable {
        let name: String?
        let description: String?
        let status: String?
    }
    
    init(from decoder: Decoder) throws {
        let event = try decoder.container(keyedBy: EventKeys.self)
        let content = try event.decodeIfPresent(Content.self, forKey: .content)
        name = content?.name
        description = content?.description
        status = AgentProjectStatus(rawValue: content?.status ?? "") ?? .active
    }
    
    init?(parsingFrom rawStateEventJSON: String) {
        guard let data = rawStateEventJSON.data(using: .utf8),
              let event = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = event
    }
}

/// Parses the full raw state event JSON returned by `getRoomStateEventsRaw` for
/// `io.element.agent.choice_request` (state key = the original message's event ID).
nonisolated struct AgentChoiceStateIndexEvent: Decodable {
    static let eventType = "io.element.agent.choice_request"
    
    let eventID: String
    let status: String?
    let question: String?
    let resolvedSelection: [String]?
    
    /// Old-protocol rooms only ever write this state once, at resolution time, always with a
    /// non-empty `resolved_selection` — so they never appear pending. That asymmetry is by design.
    ///
    /// A `cancelled` status (请旨撤销) is never pending either, even with an empty/missing
    /// `resolved_selection` — cancellation is a terminal state, not an outstanding ask.
    var isPending: Bool {
        (resolvedSelection ?? []).isEmpty && status != "cancelled"
    }
    
    private enum EventKeys: String, CodingKey {
        case stateKey = "state_key"
        case content
    }
    
    private struct Content: Decodable {
        let status: String?
        let question: String?
        let resolvedSelection: [String]?
        
        private enum CodingKeys: String, CodingKey {
            case status
            case question
            case resolvedSelection = "resolved_selection"
        }
    }
    
    init(from decoder: Decoder) throws {
        let event = try decoder.container(keyedBy: EventKeys.self)
        eventID = try event.decode(String.self, forKey: .stateKey)
        let content = try event.decode(Content.self, forKey: .content)
        status = content.status
        question = content.question
        resolvedSelection = content.resolvedSelection
    }
    
    init?(parsingFrom rawStateEventJSON: String) {
        guard let data = rawStateEventJSON.data(using: .utf8),
              let event = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = event
    }
}
