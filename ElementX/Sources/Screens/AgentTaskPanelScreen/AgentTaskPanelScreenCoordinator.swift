//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct AgentTaskPanelScreenCoordinatorParameters {
    let summaryPublisher: CurrentValuePublisher<RoomTaskSummary, Never>
}

enum AgentTaskPanelScreenCoordinatorAction {
    case presentTaskDetail(task: RoomTaskSummary.Task)
    case focusTimelineEvent(eventID: String)
}

final class AgentTaskPanelScreenCoordinator: CoordinatorProtocol {
    private let parameters: AgentTaskPanelScreenCoordinatorParameters
    private let viewModel: AgentTaskPanelScreenViewModelProtocol

    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<AgentTaskPanelScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentTaskPanelScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: AgentTaskPanelScreenCoordinatorParameters) {
        self.parameters = parameters
        viewModel = AgentTaskPanelScreenViewModel(summaryPublisher: parameters.summaryPublisher)
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .presentTaskDetail(let task):
                actionsSubject.send(.presentTaskDetail(task: task))
            case .focusTimelineEvent(let eventID):
                actionsSubject.send(.focusTimelineEvent(eventID: eventID))
            }
        }
        .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(AgentTaskPanelScreen(context: viewModel.context))
    }
}
