//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

@MainActor
struct RoomListFiltersScreenViewModelTests {
    var viewModel: RoomListFiltersScreenViewModelProtocol
    var context: RoomListFiltersScreenViewModelType.Context { viewModel.context }

    init() {
        viewModel = RoomListFiltersScreenViewModel(initialFiltersState: .init(appSettings: .volatile()))
    }

    @Test
    func togglingAFilterActivatesIt() {
        #expect(context.viewState.filtersState.isFilterActive(.unreads) == false)
        context.send(viewAction: .toggleFilter(.unreads))
        #expect(context.viewState.filtersState.isFilterActive(.unreads) == true)
    }

    @Test
    func togglingAnActiveFilterDeactivatesIt() {
        context.send(viewAction: .toggleFilter(.favourites))
        #expect(context.viewState.filtersState.isFilterActive(.favourites) == true)
        context.send(viewAction: .toggleFilter(.favourites))
        #expect(context.viewState.filtersState.isFilterActive(.favourites) == false)
    }

    @Test
    func togglingAnIncompatibleFilterIsIgnored() {
        // .invites is incompatible with .people (RoomListFilterModels.swift:57-58).
        context.send(viewAction: .toggleFilter(.people))
        #expect(context.viewState.filtersState.isFilterActive(.people) == true)

        context.send(viewAction: .toggleFilter(.invites))
        #expect(context.viewState.filtersState.isFilterActive(.invites) == false, "Activating an incompatible filter must be a no-op, not a crash")
        #expect(context.viewState.filtersState.isFilterActive(.people) == true, "The original filter must remain active")
    }

    @Test
    func clearFiltersRemovesAllActiveFilters() {
        context.send(viewAction: .toggleFilter(.unreads))
        context.send(viewAction: .toggleFilter(.favourites))
        #expect(context.viewState.filtersState.isFiltering == true)

        context.send(viewAction: .clearFilters)
        #expect(context.viewState.filtersState.isFiltering == false)
    }

    @Test
    func toggleSendsLiveFiltersChangedAction() async throws {
        var receivedStates = [RoomListFiltersState]()
        let cancellable = viewModel.actionsPublisher.sink { action in
            if case .filtersChanged(let state) = action {
                receivedStates.append(state)
            }
        }

        context.send(viewAction: .toggleFilter(.rooms))

        #expect(receivedStates.count == 1)
        #expect(receivedStates.first?.isFilterActive(.rooms) == true)
        cancellable.cancel()
    }

    @Test
    func closeSendsDismissAction() async throws {
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            switch action {
            case .dismiss: true
            default: false
            }
        }

        context.send(viewAction: .close)

        try await deferred.fulfill()
    }
}
