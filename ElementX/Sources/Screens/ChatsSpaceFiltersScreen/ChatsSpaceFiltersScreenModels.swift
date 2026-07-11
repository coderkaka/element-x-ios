//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum ChatsSpaceFiltersScreenViewModelAction {
    /// `nil` selects 全部 (unfiltered).
    case confirm(SpaceServiceFilter?)
    case manageSpaces
    case cancel
}

struct ChatsSpaceFiltersScreenViewState: BindableState {
    var filters = [SpaceServiceFilter]()
    /// User-customised order of the level-0 filters (space room IDs), live-mirrored from
    /// `AppSettings.spaceFilterOrder` — shared with the retired chip bar's own setting so a
    /// reorder made here matches what the chips used to show.
    var spaceFilterOrder: [String] = []
    /// `nil` means 全部 (unfiltered) is selected.
    var selectedSpaceFilterRoomID: String?
    /// Whether the user has an unseen invite to a 道 (Space) — the space graph backing `filters`
    /// only surfaces joined spaces, so an invited 道 can't appear as its own row here. Badges the
    /// "管理" toolbar button instead (fix-spacebar3 contract C's V1 fallback).
    var hasPendingSpaceInvites = false
    var bindings: ChatsSpaceFiltersScreenViewStateBindings

    var orderedFilters: [SpaceServiceFilter] {
        sortSpaceFilterTree(filters, byOrder: spaceFilterOrder)
    }

    var visibleFilters: [SpaceServiceFilter] {
        guard !bindings.searchQuery.isEmpty else {
            return orderedFilters
        }

        return orderedFilters.filter { filter in
            filter.room.name.localizedStandardContains(bindings.searchQuery) ||
                (filter.room.canonicalAlias ?? "").localizedStandardContains(bindings.searchQuery)
        }
    }

    /// Whether the pinned "全部" row should show as selected.
    var isAllFiltersSelected: Bool {
        selectedSpaceFilterRoomID == nil
    }

    /// The level-0 filter IDs in their current display order — backs the reorder context menu's
    /// leading/trailing edge disabling, mirroring the retired chip bar's own boundary checks.
    var topLevelFilterIDsInOrder: [String] {
        orderedFilters.filter { $0.level == 0 }.map(\.room.id)
    }
}

struct ChatsSpaceFiltersScreenViewStateBindings {
    var searchQuery = ""
}

enum ChatsSpaceFiltersScreenViewAction: CustomStringConvertible {
    case confirm(SpaceServiceFilter?)
    case manageSpaces
    case cancel
    case reorder(roomID: String, direction: MoveDirection)

    var description: String {
        switch self {
        case .confirm(let filter): "Confirm(\(filter?.room.id ?? "all"))"
        case .manageSpaces: "ManageSpaces"
        case .cancel: "Cancel"
        case .reorder(let roomID, let direction): "Reorder(\(roomID), \(direction))"
        }
    }
}
