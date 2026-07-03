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

    /// - Parameters:
    ///   - originalJSON: the raw Matrix event JSON from `EventTimelineItemProxy.debugInfo.originalJSON`.
    ///     The Rust SDK only exposes the standard `body` field for custom msgtypes via `MessageType.other`,
    ///     so `question`/`options`/`multi_select`/`resolved_selection` have to be recovered by hand from
    ///     the raw event — the same reasoning `AgentTurnRoomTimelineItemContent` documents for `tool_calls`.
    ///   - latestEditJSON: `EventTimelineItemProxy.debugInfo.latestEditJSON`, non-nil once the agent has
    ///     edited this message to resolve it. Whichever of the two is non-nil and parses successfully wins,
    ///     preferring the edit — this is how the client learns `resolved_selection` without any cross-event
    ///     reply-scanning, per this plan's design doc.
    init(body: String, parsingFrom originalJSON: String?, latestEditJSON: String?) {
        self.body = body
        let fields = Self.parseFields(from: latestEditJSON) ?? Self.parseFields(from: originalJSON)
        question = fields?.question ?? ""
        options = fields?.options ?? []
        multiSelect = fields?.multiSelect ?? false
        resolvedSelection = fields?.resolvedSelection
    }

    private struct Fields: Decodable {
        let question: String
        let options: [ChoiceOption]
        let multiSelect: Bool
        let resolvedSelection: [String]?

        enum CodingKeys: String, CodingKey {
            case question
            case options
            case multiSelect = "multi_select"
            case resolvedSelection = "resolved_selection"
        }

        // Custom init so a missing `options` key falls back to `[]` instead of failing the whole
        // decode (the synthesized Decodable would throw keyNotFound, discarding `question` too).
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            question = try container.decode(String.self, forKey: .question)
            options = try container.decodeIfPresent([ChoiceOption].self, forKey: .options) ?? []
            multiSelect = try container.decode(Bool.self, forKey: .multiSelect)
            resolvedSelection = try container.decodeIfPresent([String].self, forKey: .resolvedSelection)
        }
    }

    /// Matrix message edits (`m.replace`) nest their replacement content under `m.new_content`, while an
    /// unedited event's fields live directly under `content`. Whether `latestEditJSON` is the raw edit event
    /// (needing this unwrap) or already-flattened replacement content (not needing it) wasn't discoverable
    /// from the vendored SDK bindings — this handles both shapes without needing to know which is real.
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
