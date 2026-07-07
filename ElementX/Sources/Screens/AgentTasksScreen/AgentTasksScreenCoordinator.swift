//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct AgentTasksScreenCoordinatorParameters {
    let agentTaskIndexService: AgentTaskIndexServiceProtocol
    let appSettings: AppSettings
}

enum AgentTasksScreenCoordinatorAction {
    case presentCanvasSteps(roomID: String, taskID: String)
}

final class AgentTasksScreenCoordinator: CoordinatorProtocol {
    private let parameters: AgentTasksScreenCoordinatorParameters
    private let viewModel: AgentTasksScreenViewModelProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<AgentTasksScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentTasksScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AgentTasksScreenCoordinatorParameters) {
        self.parameters = parameters
        viewModel = AgentTasksScreenViewModel(agentTaskIndexService: parameters.agentTaskIndexService, appSettings: parameters.appSettings)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .presentCanvasSteps(let roomID, let taskID):
                actionsSubject.send(.presentCanvasSteps(roomID: roomID, taskID: taskID))
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(AgentTasksScreen(context: viewModel.context))
    }
}
