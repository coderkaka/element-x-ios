//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AgentTasksScreenViewModelType = StateStoreViewModelV2<AgentTasksScreenViewState, AgentTasksScreenViewAction>

class AgentTasksScreenViewModel: AgentTasksScreenViewModelType, AgentTasksScreenViewModelProtocol {
    private let actionsSubject: PassthroughSubject<AgentTasksScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentTasksScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(agentTaskIndexService: AgentTaskIndexServiceProtocol) {
        super.init(initialViewState: AgentTasksScreenViewState())
        
        // No queue hop: the service publishes on the main actor and the synchronous
        // initial emission populates state before the first render (previews rely on this).
        agentTaskIndexService.tasksPublisher
            .sink { [weak self] tasks in
                guard let self else { return }
                state.unresolvedTasks = tasks.filter { !$0.isResolved }
                state.resolvedTasks = tasks.filter(\.isResolved)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public
    
    override func process(viewAction: AgentTasksScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .taskTapped(let task):
            actionsSubject.send(.presentRoom(roomID: task.roomID))
        }
    }
}
