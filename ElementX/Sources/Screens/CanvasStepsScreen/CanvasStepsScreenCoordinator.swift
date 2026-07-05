//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct CanvasStepsScreenCoordinatorParameters {
    let title: String
    let steps: [CanvasStep]
    let taskID: String
    let threadRootEventID: String?
    let roomProxy: JoinedRoomProxyProtocol
}

enum CanvasStepsScreenCoordinatorAction {
    case dismiss
    case presentThread(threadRootEventID: String)
}

final class CanvasStepsScreenCoordinator: CoordinatorProtocol {
    private let parameters: CanvasStepsScreenCoordinatorParameters
    private let viewModel: CanvasStepsScreenViewModelProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<CanvasStepsScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CanvasStepsScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: CanvasStepsScreenCoordinatorParameters) {
        self.parameters = parameters
        viewModel = CanvasStepsScreenViewModel(title: parameters.title,
                                               steps: parameters.steps,
                                               taskID: parameters.taskID,
                                               threadRootEventID: parameters.threadRootEventID,
                                               roomProxy: parameters.roomProxy)
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss:
                actionsSubject.send(.dismiss)
            case .presentThread(let threadRootEventID):
                actionsSubject.send(.presentThread(threadRootEventID: threadRootEventID))
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(CanvasStepsScreen(context: viewModel.context))
    }
}
