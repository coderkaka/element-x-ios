//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias RoomListFiltersScreenViewModelType = StateStoreViewModelV2<RoomListFiltersScreenViewState, RoomListFiltersScreenViewAction>

class RoomListFiltersScreenViewModel: RoomListFiltersScreenViewModelType, RoomListFiltersScreenViewModelProtocol, Identifiable {
    private let actionsSubject: PassthroughSubject<RoomListFiltersScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<RoomListFiltersScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    let id = UUID()

    init(initialFiltersState: RoomListFiltersState) {
        super.init(initialViewState: RoomListFiltersScreenViewState(filtersState: initialFiltersState))
    }

    // MARK: - Public

    override func process(viewAction: RoomListFiltersScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .toggleFilter(let filter):
            if state.filtersState.isFilterActive(filter) {
                state.filtersState.deactivateFilter(filter)
            } else if state.filtersState.availableFilters.contains(filter) {
                state.filtersState.activateFilter(filter)
            } else {
                return
            }
            actionsSubject.send(.filtersChanged(state.filtersState))
        case .clearFilters:
            state.filtersState.clearFilters()
            actionsSubject.send(.filtersChanged(state.filtersState))
        case .close:
            actionsSubject.send(.dismiss)
        }
    }
}
