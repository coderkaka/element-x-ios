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
    let sender: TimelineItemSender
    let body: AttributedString?
    let timestamp: Date
}
