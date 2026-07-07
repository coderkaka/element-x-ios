//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated enum AgentObjectiveStatus: String {
    case active, done, abandoned
}

/// A 标的(阶段目标)— a phase-level objective inside a 案(project room), sitting between
/// `AgentProjectSummary` (single, long-lived, "why this room exists") and `AgentTaskSummary`/
/// pending choices (execution-level). A room can have several, tracked independently by
/// `objectiveID`. See `element-agent-protocol.md` §3.4.
nonisolated struct AgentObjectiveSummary: Identifiable, Equatable {
    let roomID: String
    let objectiveID: String
    let title: String
    let status: AgentObjectiveStatus
    /// Read-only qualitative checklist for "when is this phase done" — not the same as a
    /// task's quantitative `metric{current,target,unit}`. Authoritative completion signal is
    /// always `status`, never derived from this list.
    let successMetrics: [String]
    /// Read-only list of options on the table at this objective's decision point. The actual
    /// decision still goes through the existing `choice_request` flow — this is background,
    /// not itself a decision mechanism.
    let exitOptions: [String]
    let priority: Int
    let updatedAt: Date
    
    var id: String {
        "\(roomID)|\(objectiveID)"
    }
}

/// Parses the full raw state event JSON returned by `getRoomStateEventsRaw` for
/// `io.element.agent.objective` (state key = `objective_id`).
nonisolated struct AgentObjectiveStateEvent: Decodable {
    static let eventType = "io.element.agent.objective"
    
    let objectiveID: String
    let title: String
    let status: AgentObjectiveStatus
    let successMetrics: [String]
    let exitOptions: [String]
    let priority: Int
    let updatedAt: Date
    
    private enum EventKeys: String, CodingKey {
        case stateKey = "state_key"
        case content
    }
    
    private struct Content: Decodable {
        let title: String?
        let status: String?
        let successMetrics: [String]?
        let exitOptions: [String]?
        let priority: Int?
        let updatedAt: UInt64?
        
        private enum CodingKeys: String, CodingKey {
            case title
            case status
            case successMetrics = "success_metrics"
            case exitOptions = "exit_options"
            case priority
            case updatedAt = "updated_at"
        }
    }
    
    init(from decoder: Decoder) throws {
        let event = try decoder.container(keyedBy: EventKeys.self)
        objectiveID = try event.decode(String.self, forKey: .stateKey)
        let content = try event.decode(Content.self, forKey: .content)
        title = content.title ?? objectiveID
        status = content.status.flatMap(AgentObjectiveStatus.init(rawValue:)) ?? .active
        successMetrics = content.successMetrics ?? []
        exitOptions = content.exitOptions ?? []
        priority = content.priority ?? 0
        updatedAt = content.updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } ?? .distantPast
    }
    
    init?(parsingFrom rawStateEventJSON: String) {
        guard let data = rawStateEventJSON.data(using: .utf8),
              let event = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = event
    }
}
