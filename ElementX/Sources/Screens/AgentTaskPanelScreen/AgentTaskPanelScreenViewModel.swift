//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AgentTaskPanelScreenViewModelType = StateStoreViewModelV2<AgentTaskPanelScreenViewState, AgentTaskPanelScreenViewAction>

class AgentTaskPanelScreenViewModel: AgentTaskPanelScreenViewModelType, AgentTaskPanelScreenViewModelProtocol {
    private let actionsSubject: PassthroughSubject<AgentTaskPanelScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentTaskPanelScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(summaryPublisher: CurrentValuePublisher<RoomTaskSummary, Never>, appSettings: AppSettings) {
        super.init(initialViewState: AgentTaskPanelScreenViewState(terminology: .init(scenario: appSettings.terminologyScenario)))
        
        // No queue hop: the timeline publishes on the main actor and the synchronous
        // initial emission populates state before the first render (previews rely on this).
        summaryPublisher
            .sink { [weak self] summary in
                guard let self else { return }
                state.pendingChoices = summary.pendingChoices
                state.activeTasks = summary.activeTasks
                state.doneTasks = summary.doneTasks
            }
            .store(in: &cancellables)
        
        appSettings.terminologyScenarioPublisher
            .sink { [weak self] scenario in
                self?.state.terminology = .init(scenario: scenario)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public
    
    override func process(viewAction: AgentTaskPanelScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .taskTapped(let task):
            actionsSubject.send(.presentTaskDetail(task: task))
        case .choiceTapped(let eventID):
            actionsSubject.send(.focusTimelineEvent(eventID: eventID))
        }
    }
}
