//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct RoomListFiltersScreen: View {
    @Bindable var context: RoomListFiltersScreenViewModel.Context
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    ForEach(visibleFilters) { filter in
                        ListRow(label: .plain(title: filter.localizedName),
                                kind: .toggle(binding(for: filter)))
                    }
                }
            }
            .compoundList()
            .toolbar { toolbar }
            .navigationTitle(UntranslatedL10n.screenRoomlistFiltersTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }
    
    /// Only show filters that are either already active, or still selectable given the current
    /// selection — mirrors `RoomListFiltersState.availableFilters` excluding mutually-exclusive
    /// options from the list entirely, matching today's chip-row behaviour.
    ///
    /// `.people` is excluded: 政事 (chats tab) is group-rooms-only now, DMs live in 书信,
    /// so this would be a dead toggle. The enum case itself stays — 书信's provider still uses it.
    private var visibleFilters: [RoomListFilter] {
        RoomListFilter.allCases.filter { filter in
            filter != .people &&
                (context.viewState.filtersState.isFilterActive(filter) || context.viewState.filtersState.availableFilters.contains(filter))
        }
    }
    
    private func binding(for filter: RoomListFilter) -> Binding<Bool> {
        Binding<Bool>(get: {
            context.viewState.filtersState.isFilterActive(filter)
        }, set: { _, _ in
            context.send(viewAction: .toggleFilter(filter))
        })
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if context.viewState.filtersState.isFiltering {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.actionClear) {
                    context.send(viewAction: .clearFilters)
                }
            }
        }
        
        ToolbarItem(placement: .primaryAction) {
            ToolbarButton(role: .close) {
                context.send(viewAction: .close)
            }
        }
    }
}

// MARK: - Previews

struct RoomListFiltersScreen_Previews: PreviewProvider, TestablePreview {
    static let noFiltersViewModel = RoomListFiltersScreenViewModel(initialFiltersState: .init(appSettings: .volatile()))
    static let someFiltersViewModel = RoomListFiltersScreenViewModel(initialFiltersState: .init(activeFilters: [.rooms, .favourites], appSettings: .volatile()))
    
    static var previews: some View {
        RoomListFiltersScreen(context: noFiltersViewModel.context)
            .previewDisplayName("No active filters")
        RoomListFiltersScreen(context: someFiltersViewModel.context)
            .previewDisplayName("Rooms + Favourites active")
    }
}
