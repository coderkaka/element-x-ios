//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct MessagesScreenCoordinatorParameters {
    let userSession: UserSessionProtocol
    let roomSummaryProvider: RoomSummaryProviderProtocol
    let appSettings: AppSettings
}

enum MessagesScreenCoordinatorAction {
    case presentRoom(roomID: String)
    case showSettings
}

final class MessagesScreenCoordinator: CoordinatorProtocol {
    private let parameters: MessagesScreenCoordinatorParameters
    private let viewModel: MessagesScreenViewModelProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<MessagesScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<MessagesScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: MessagesScreenCoordinatorParameters) {
        self.parameters = parameters
        viewModel = MessagesScreenViewModel(userSession: parameters.userSession,
                                            roomSummaryProvider: parameters.roomSummaryProvider,
                                            appSettings: parameters.appSettings)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .presentRoom(let roomID):
                actionsSubject.send(.presentRoom(roomID: roomID))
            case .showSettings:
                actionsSubject.send(.showSettings)
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(MessagesScreen(context: viewModel.context))
    }
}
