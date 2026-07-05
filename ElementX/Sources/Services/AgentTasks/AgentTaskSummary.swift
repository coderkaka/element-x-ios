//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct AgentTaskSummary: Identifiable, Equatable {
    let roomID: String
    let roomName: String
    let taskID: String
    /// `nil` when the state event doesn't carry a title (older agents) — UI shows `taskID`.
    let title: String?
    let isResolved: Bool
    let doneStepCount: Int
    let totalStepCount: Int

    var id: String { "\(roomID)|\(taskID)" }
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

    private enum EventKeys: String, CodingKey {
        case stateKey = "state_key"
        case content
    }

    private struct Content: Decodable {
        let title: String?
        let status: String
        let steps: [CanvasStep]?
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
    }

    init?(parsingFrom rawStateEventJSON: String) {
        guard let data = rawStateEventJSON.data(using: .utf8),
              let event = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = event
    }
}
