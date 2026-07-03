//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum RoomListFiltersScreenViewModelAction {
    case filtersChanged(RoomListFiltersState)
    case dismiss
}

struct RoomListFiltersScreenViewState: BindableState {
    var filtersState: RoomListFiltersState
}

enum RoomListFiltersScreenViewAction: CustomStringConvertible {
    case toggleFilter(RoomListFilter)
    case clearFilters
    case close

    var description: String {
        switch self {
        case .toggleFilter(let filter): "Toggle \(filter)"
        case .clearFilters: "ClearFilters"
        case .close: "Close"
        }
    }
}
