//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// sourcery: AutoMockable
protocol MessageSearchProxyProtocol {
    var resultsPublisher: CurrentValuePublisher<[MessageSearchResultItem], Never> { get }
    var paginationStatePublisher: CurrentValuePublisher<MessageSearchPaginationState, Never> { get }
    
    /// Sets (or updates) the search query, clearing existing results and restarting pagination from scratch.
    func search(query: String) async -> Result<Void, MessageSearchError>
    /// Loads the next page of results. No-ops if a page is already loading or the end has been reached.
    func paginate() async -> Result<Void, MessageSearchError>
    
    /// Indexes another large batch of older history for rooms that haven't been fully searched yet,
    /// picking up where the last pass (automatic or explicit) left off. Not meant to be called
    /// frequently — each call can take a while, since it may page in a room's history from the
    /// server. Returns `true` once every room's full history is indexed, `false` if there's still
    /// more to search — call again to continue.
    func searchOlderMessages() async -> Bool
}

enum MessageSearchError: Error {
    case searchFailed
    case paginationFailed
}

enum MessageSearchPaginationState: Equatable {
    case idle(endReached: Bool)
    case loading
}

/// A message (room timeline event) matching a search query, with its content and sender already resolved.
nonisolated struct MessageSearchResultItem: Identifiable, Equatable {
    /// The matching event's ID, unique across the whole search result set.
    var id: String {
        eventID
    }
    
    let eventID: String
    let roomID: String
    /// The display name of the room the message is in, for cross-room search results. `nil` if the
    /// room's name couldn't be resolved.
    let roomName: String?
    let sender: TimelineItemSender
    let body: AttributedString?
    let timestamp: Date
}
