//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct CanvasStep: Hashable, Decodable {
    enum Status: Hashable {
        case pending
        case inProgress
        case done
        /// Any status value the client doesn't recognise yet — kept instead of dropped so a future
        /// agent backend can introduce new statuses without this client silently losing data.
        case other(String)
    }
    
    let id: String
    let label: String
    let status: Status
}

extension CanvasStep.Status: Decodable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "pending": self = .pending
        case "in_progress": self = .inProgress
        case "done": self = .done
        default: self = .other(raw)
        }
    }
}

nonisolated struct AgentCanvasStepsRoomTimelineItemContent: Hashable {
    /// The custom `m.room.message` msgtype this content type is built from.
    static let msgType = "io.element.agent.canvas.steps"
    
    let body: String
    let taskID: String
    let title: String
    let isResolved: Bool
    let steps: [CanvasStep]
    
    init(body: String, taskID: String = "", title: String = "", isResolved: Bool = false, steps: [CanvasStep] = []) {
        self.body = body
        self.taskID = taskID
        self.title = title
        self.isResolved = isResolved
        self.steps = steps
    }
    
    /// - Parameters:
    ///   - originalJSON: the raw Matrix event JSON from `EventTimelineItemProxy.debugInfo.originalJSON`.
    ///     The Rust SDK only exposes `body` for custom msgtypes via `MessageType.other`, so
    ///     `task_id`/`title`/`status`/`steps` have to be recovered by hand, same reasoning
    ///     `AgentTurnRoomTimelineItemContent` documents for `tool_calls`.
    ///   - latestEditJSON: `EventTimelineItemProxy.debugInfo.latestEditJSON`, non-nil once the agent
    ///     has edited this message to update progress. Confirmed this session (via
    ///     `io.element.agent.choice_request`'s Task 1, independently re-verified against live
    ///     `matrix-rust-sdk` source) to be the raw `m.replace` edit event, replacement fields nested
    ///     under `m.new_content` — this parser unwraps that directly, no dual-shape handling needed.
    init(body: String, parsingFrom originalJSON: String?, latestEditJSON: String?) {
        self.body = body
        let fields = Self.parseFields(from: latestEditJSON) ?? Self.parseFields(from: originalJSON)
        taskID = fields?.taskID ?? ""
        title = fields?.title ?? ""
        isResolved = fields?.status == "done"
        steps = fields?.steps ?? []
    }
    
    private struct Fields: Decodable {
        let taskID: String
        let title: String
        let status: String
        let steps: [CanvasStep]?
        
        enum CodingKeys: String, CodingKey {
            case taskID = "task_id"
            case title
            case status
            case steps
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            taskID = try container.decode(String.self, forKey: .taskID)
            title = try container.decode(String.self, forKey: .title)
            status = try container.decode(String.self, forKey: .status)
            steps = try? container.decodeIfPresent([CanvasStep].self, forKey: .steps)
        }
    }
    
    private struct ContentEnvelope: Decodable {
        let fields: Fields
        
        enum CodingKeys: String, CodingKey {
            case newContent = "m.new_content"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let newContent = try container.decodeIfPresent(Fields.self, forKey: .newContent) {
                fields = newContent
            } else {
                fields = try Fields(from: decoder)
            }
        }
    }
    
    private struct EventEnvelope: Decodable {
        let content: ContentEnvelope
    }
    
    private static func parseFields(from json: String?) -> Fields? {
        guard let data = json?.data(using: .utf8) else { return nil }
        guard let event = try? JSONDecoder().decode(EventEnvelope.self, from: data) else { return nil }
        return event.content.fields
    }
}
