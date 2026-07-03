//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct ToolCallSummary: Hashable {
    enum Status: Hashable {
        case pending
        case done
        case failed
        /// Any status value the client doesn't recognise yet — kept instead of dropped so a future
        /// agent backend can introduce new statuses without this client silently losing data.
        case other(String)
    }

    let name: String
    let status: Status
    let summary: String
}

extension ToolCallSummary: Decodable {}

extension ToolCallSummary.Status: Decodable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "pending": self = .pending
        case "done": self = .done
        case "failed": self = .failed
        default: self = .other(raw)
        }
    }
}

nonisolated struct AgentTurnRoomTimelineItemContent: Hashable {
    /// The custom `m.room.message` msgtype this content type is built from.
    static let msgType = "io.element.agent.turn"

    let body: String
    let toolCalls: [ToolCallSummary]

    init(body: String, toolCalls: [ToolCallSummary] = []) {
        self.body = body
        self.toolCalls = toolCalls
    }

    /// - Parameter originalJSON: the raw Matrix event JSON from `EventTimelineItemProxy.debugInfo.originalJSON`.
    ///   The Rust SDK only exposes the standard `body` field for custom msgtypes via `MessageType.other`,
    ///   so `tool_calls` has to be recovered by hand from the raw event. `originalJSON` is always the
    ///   *full* event (confirmed against `matrix-rust-sdk` source: `original_json: Option<Raw<AnySyncTimelineEvent>>`,
    ///   `crates/matrix-sdk-ui/src/timeline/event_item/mod.rs:135`), so `tool_calls` lives under `content`.
    init(body: String, parsingToolCallsFrom originalJSON: String?) {
        self.body = body
        toolCalls = Self.parseToolCalls(from: originalJSON)
    }

    private static func parseToolCalls(from originalJSON: String?) -> [ToolCallSummary] {
        guard let data = originalJSON?.data(using: .utf8) else { return [] }

        struct ContentEnvelope: Decodable {
            let toolCalls: [ToolCallSummary]

            enum CodingKeys: String, CodingKey {
                case toolCalls = "tool_calls"
            }
        }

        struct EventEnvelope: Decodable {
            let content: ContentEnvelope
        }

        guard let event = try? JSONDecoder().decode(EventEnvelope.self, from: data) else { return [] }
        return event.content.toolCalls
    }
}
