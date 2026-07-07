//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// A quantifiable progress target on a task — `io.element.agent.canvas.steps`' optional
/// `metric{current,target,unit}` field (`element-agent-protocol.md` §3.2). Only present
/// for tasks with a natural quantifiable goal (e.g. "提分到130分"); most tasks have none.
nonisolated struct AgentTaskMetric: Decodable, Equatable {
    let current: Double
    let target: Double
    let unit: String
    
    var formattedCurrent: String {
        Self.format(current)
    }
    
    var formattedTarget: String {
        Self.format(target)
    }
    
    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

nonisolated struct AgentTaskSummary: Identifiable, Equatable {
    let roomID: String
    let roomName: String
    let taskID: String
    /// `nil` when the state event doesn't carry a title (older agents) — UI shows `taskID`.
    let title: String?
    let isResolved: Bool
    let doneStepCount: Int
    let totalStepCount: Int
    var metric: AgentTaskMetric?
    
    var id: String {
        "\(roomID)|\(taskID)"
    }
}

/// Parses the full raw state event JSON returned by `getRoomStateEventsRaw` for
/// `io.element.agent.canvas.steps` (state key = task_id).
nonisolated struct AgentTaskStateEvent: Decodable {
    static let eventType = "io.element.agent.canvas.steps"
    
    let taskID: String
    let title: String?
    let isResolved: Bool
    let doneStepCount: Int
    let totalStepCount: Int
    let metric: AgentTaskMetric?
    
    private enum EventKeys: String, CodingKey {
        case stateKey = "state_key"
        case content
    }
    
    private struct Content: Decodable {
        let title: String?
        let status: String
        let steps: [CanvasStep]?
        let metric: AgentTaskMetric?
    }
    
    init(from decoder: Decoder) throws {
        let event = try decoder.container(keyedBy: EventKeys.self)
        taskID = try event.decode(String.self, forKey: .stateKey)
        let content = try event.decode(Content.self, forKey: .content)
        title = content.title
        isResolved = content.status == "done"
        let steps = content.steps ?? []
        doneStepCount = steps.count { $0.status == .done }
        totalStepCount = steps.count
        metric = content.metric
    }
    
    init?(parsingFrom rawStateEventJSON: String) {
        guard let data = rawStateEventJSON.data(using: .utf8),
              let event = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = event
    }
}

/// One historical revision of a task's `metric` field, read via
/// `ClientProxyProtocol.getRoomStateEventHistoryRaw` — reconstructs a value-over-time trend
/// from the room's timeline, since the state store itself only ever holds the latest revision.
nonisolated struct AgentTaskMetricHistoryPoint: Decodable, Equatable {
    let metric: AgentTaskMetric
    let date: Date
    
    init(metric: AgentTaskMetric, date: Date) {
        self.metric = metric
        self.date = date
    }
    
    private enum EventKeys: String, CodingKey {
        case originServerTimestamp = "origin_server_ts"
        case content
    }
    
    private struct Content: Decodable {
        let metric: AgentTaskMetric?
    }
    
    init(from decoder: Decoder) throws {
        let event = try decoder.container(keyedBy: EventKeys.self)
        let timestampMs = try event.decode(UInt64.self, forKey: .originServerTimestamp)
        date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        guard let metric = try event.decode(Content.self, forKey: .content).metric else {
            throw DecodingError.valueNotFound(AgentTaskMetric.self,
                                              .init(codingPath: decoder.codingPath, debugDescription: "Missing metric field"))
        }
        self.metric = metric
    }
    
    init?(parsingFrom rawStateEventJSON: String) {
        guard let data = rawStateEventJSON.data(using: .utf8),
              let point = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = point
    }
}
