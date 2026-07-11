//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias ChatsSpaceFiltersScreenViewModelType = StateStoreViewModelV2<ChatsSpaceFiltersScreenViewState, ChatsSpaceFiltersScreenViewAction>

class ChatsSpaceFiltersScreenViewModel: ChatsSpaceFiltersScreenViewModelType, ChatsSpaceFiltersScreenViewModelProtocol, Identifiable {
    private let spaceService: SpaceServiceProxyProtocol
    private let appSettings: AppSettings

    private let actionsSubject: PassthroughSubject<ChatsSpaceFiltersScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<ChatsSpaceFiltersScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    let id = UUID()

    init(spaceService: SpaceServiceProxyProtocol,
         appSettings: AppSettings,
         hasPendingSpaceInvites: Bool,
         mediaProvider: MediaProviderProtocol) {
        self.spaceService = spaceService
        self.appSettings = appSettings

        super.init(initialViewState: ChatsSpaceFiltersScreenViewState(spaceFilterOrder: appSettings.spaceFilterOrder,
                                                                       selectedSpaceFilterRoomID: appSettings.selectedSpaceFilterRoomID,
                                                                       hasPendingSpaceInvites: hasPendingSpaceInvites,
                                                                       bindings: .init()),
                   mediaProvider: mediaProvider)

        state.filters = spaceService.spaceFilterPublisher.value

        spaceService.spaceFilterPublisher.sink { [weak self] filters in
            self?.state.filters = filters
        }
        .store(in: &cancellables)

        // Keeps the panel's own order/selection live — a reorder or selection made elsewhere
        // (e.g. this same panel reopened, or the other tab) must still be reflected here.
        appSettings.spaceFilterOrderPublisher
            .sink { [weak self] order in
                self?.state.spaceFilterOrder = order
            }
            .store(in: &cancellables)

        appSettings.selectedSpaceFilterRoomIDPublisher
            .sink { [weak self] roomID in
                self?.state.selectedSpaceFilterRoomID = roomID
            }
            .store(in: &cancellables)
    }

    // MARK: - Public

    override func process(viewAction: ChatsSpaceFiltersScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .confirm(let filter):
            actionsSubject.send(.confirm(filter))
        case .manageSpaces:
            actionsSubject.send(.manageSpaces)
        case .cancel:
            actionsSubject.send(.cancel)
        case .reorder(let roomID, let direction):
            reorder(roomID: roomID, direction: direction)
        }
    }

    // MARK: - Private

    /// Mirrors the retired chip bar's own reorder logic (previously duplicated across
    /// `HomeScreenViewModel`/`AgentTasksScreenViewModel`, now centralised here since the panel is
    /// the single place a reorder can be started from, fix-spacebar3 contract D).
    private func reorder(roomID: String, direction: MoveDirection) {
        var order = state.topLevelFilterIDsInOrder
        guard let currentIndex = order.firstIndex(of: roomID) else { return }

        let swapIndex = switch direction {
        case .left: currentIndex - 1
        case .right: currentIndex + 1
        }
        guard order.indices.contains(swapIndex) else { return } // Already at an edge.

        order.swapAt(currentIndex, swapIndex)
        appSettings.spaceFilterOrder = order
        // `state.spaceFilterOrder` updates via the `spaceFilterOrderPublisher` subscription above.
    }
}
