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
    
    /// - Parameter originalJSON: the raw Matrix event JSON from `EventTimelineItemProxy.debugInfo.originalJSON`.
    ///   The Rust SDK only exposes `body` for custom msgtypes via `MessageType.other`, so
    ///   `task_id`/`title`/`status`/`steps` have to be recovered by hand, same reasoning
    ///   `AgentTurnRoomTimelineItemContent` documents for `tool_calls`.
    ///
    ///   This is the *initial* progress only. Later updates live in a `io.element.agent.canvas.steps`
    ///   room state event (state key = `task_id`), read separately via `getStateEventRaw` — see
    ///   `AgentCanvasStepsRoomTimelineView`.
    init(body: String, parsingFrom originalJSON: String?) {
        self.body = body
        let fields = Self.parseFields(from: originalJSON)
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
    
    private struct EventEnvelope: Decodable {
        let content: Fields
    }
    
    private static func parseFields(from json: String?) -> Fields? {
        guard let data = json?.data(using: .utf8) else { return nil }
        guard let event = try? JSONDecoder().decode(EventEnvelope.self, from: data) else { return nil }
        return event.content
    }
}

/// The `io.element.agent.canvas.steps` room state event content, keyed by `task_id`. Its `status`/
/// `steps` are how the client learns progress updates, without depending on message edits.
nonisolated struct AgentCanvasStepsStateContent: Decodable {
    let isResolved: Bool
    let steps: [CanvasStep]
    let title: String?
    let threadRootEventID: String?
    let updatedAt: Date?
    /// The 标的(objective) this task belongs to, if any — optional back-reference per
    /// `element-agent-protocol.md` §3.4. Drives the 案卷面板's per-objective grouping.
    let objectiveID: String?
    
    private enum CodingKeys: String, CodingKey {
        case status
        case steps
        case title
        case threadRootEventID = "thread_root_id"
        case updatedAt = "updated_at"
        case objectiveID = "objective_id"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isResolved = try container.decode(String.self, forKey: .status) == "done"
        steps = try container.decodeIfPresent([CanvasStep].self, forKey: .steps) ?? []
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        threadRootEventID = try? container.decodeIfPresent(String.self, forKey: .threadRootEventID)
        // Milliseconds since the epoch on the wire.
        updatedAt = (try? container.decodeIfPresent(UInt64.self, forKey: .updatedAt))
            .flatMap { $0 }
            .map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        objectiveID = try? container.decodeIfPresent(String.self, forKey: .objectiveID)
    }
    
    /// - Parameter rawStateEventJSON: the full raw state event JSON string returned by
    ///   `getStateEventRaw`, i.e. `{"type": ..., "state_key": ..., "content": {"status": ..., "steps": [...]}, ...}`.
    init?(parsingFrom rawStateEventJSON: String?) {
        guard let data = rawStateEventJSON?.data(using: .utf8) else { return nil }
        
        struct EventEnvelope: Decodable {
            let content: AgentCanvasStepsStateContent
        }
        
        guard let event = try? JSONDecoder().decode(EventEnvelope.self, from: data) else { return nil }
        self = event.content
    }
}
