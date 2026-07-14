//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum SearchScreenViewModelAction {
    case presentRoom(roomID: String, eventID: String? = nil)
    case cancel
}

struct SearchScreenViewState: BindableState {
    var rooms = [SearchScreenRoom]()
    var messageResults = [MessageSearchResultItem]()
    var bindings: SearchScreenViewStateBindings
    
    /// Whether there's still older, not-yet-indexed history that `searchOlderMessages` could
    /// search — starts optimistic (`true`) since it isn't known until the first attempt returns.
    var hasMoreHistoryToSearch = true
    var isSearchingOlderMessages = false
    
    var isSearching: Bool {
        !bindings.searchQuery.isEmpty
    }
}

struct SearchScreenViewStateBindings {
    var searchQuery = ""
}

enum SearchScreenViewAction {
    case appeared
    case selectRoom(roomID: String)
    case selectMessageResult(roomID: String, eventID: String)
    case reachedTop
    case reachedBottom
    case reachedMessageResultsBottom
    case searchOlderMessages
    case cancel
}

struct SearchScreenRoom: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let avatar: RoomAvatar
}
