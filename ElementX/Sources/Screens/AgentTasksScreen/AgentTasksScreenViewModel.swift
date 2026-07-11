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
    
    private let appSettings: AppSettings
    private let agentIndexService: AgentIndexServiceProtocol
    
    init(userSession: UserSessionProtocol,
         agentIndexService: AgentIndexServiceProtocol,
         spaceService: SpaceServiceProxyProtocol,
         appSettings: AppSettings) {
        self.appSettings = appSettings
        self.agentIndexService = agentIndexService
        super.init(initialViewState: AgentTasksScreenViewState(userID: userSession.clientProxy.userID,
                                                               viewMode: appSettings.agentTasksViewMode,
                                                               terminology: .init(scenario: appSettings.terminologyScenario)),
                   mediaProvider: userSession.mediaProvider)
        
        userSession.clientProxy.userAvatarURLPublisher
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.userAvatarURL, on: self)
            .store(in: &cancellables)
        
        userSession.clientProxy.userDisplayNamePublisher
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.userDisplayName, on: self)
            .store(in: &cancellables)
        
        // No queue hop: the services publish on the main actor and the synchronous
        // initial emission populates state before the first render (previews rely on this).
        Publishers.CombineLatest(agentIndexService.tasksPublisher, spaceService.spaceFilterPublisher)
            .sink { [weak self] tasks, spaceFilters in
                guard let self else { return }
                state.unresolvedTasks = tasks.filter { !$0.isResolved }
                state.resolvedTasks = tasks.filter(\.isResolved)
                state.kanbanColumns = Self.makeKanbanColumns(tasks: tasks, spaceFilters: spaceFilters, terminology: state.terminology)
                state.metricTasks = tasks.filter { $0.metric != nil }
            }
            .store(in: &cancellables)
        
        appSettings.terminologyScenarioPublisher
            .sink { [weak self] scenario in
                guard let self else { return }
                state.terminology = .init(scenario: scenario)
                state.kanbanColumns = Self.makeKanbanColumns(tasks: state.unresolvedTasks + state.resolvedTasks,
                                                             spaceFilters: spaceService.spaceFilterPublisher.value,
                                                             terminology: state.terminology)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public
    
    override func process(viewAction: AgentTasksScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .taskTapped(let task):
            actionsSubject.send(.presentCanvasSteps(roomID: task.roomID, taskID: task.taskID))
        case .setViewMode(let mode):
            appSettings.agentTasksViewMode = mode
            state.viewMode = mode
        case .loadMetricHistory(let task):
            loadMetricHistory(for: task)
        case .showSettings:
            actionsSubject.send(.showSettings)
        }
    }
    
    // MARK: - Private
    
    /// Groups tasks by the 道 (space) their room sits under, in the same order as
    /// `spaceFilters` (mirroring the order the 道 chips use elsewhere). A room can have
    /// multiple parent spaces, so a task may legitimately appear in more than one column.
    /// Tasks whose room isn't under any joined 道 land in a trailing fallback column.
    private static func makeKanbanColumns(tasks: [AgentTaskSummary],
                                          spaceFilters: [SpaceServiceFilter],
                                          terminology: AppTerminology) -> [AgentTasksKanbanColumn] {
        // De-dupe by space id first: a space reachable via two parent paths in the 道 graph can
        // appear twice, which would give `ForEach(kanbanColumns)` duplicate ids.
        var seenSpaceIDs = Set<String>()
        let uniqueFilters = spaceFilters.filter { seenSpaceIDs.insert($0.room.id).inserted }
        
        var columns = uniqueFilters.map { filter in
            AgentTasksKanbanColumn(id: filter.room.id,
                                   title: filter.room.name,
                                   tasks: tasks.filter { filter.descendants.contains($0.roomID) })
        }
        columns.removeAll { $0.tasks.isEmpty }
        
        let unassignedTasks = tasks.filter { task in !spaceFilters.contains { $0.descendants.contains(task.roomID) } }
        if !unassignedTasks.isEmpty {
            columns.append(AgentTasksKanbanColumn(id: "unassigned", title: terminology.kanbanUnassignedColumn, tasks: unassignedTasks))
        }
        
        return columns
    }
    
    private func loadMetricHistory(for task: AgentTaskSummary) {
        guard state.metricHistories[task.id] == nil, !state.loadingMetricTaskIDs.contains(task.id) else {
            return
        }
        state.loadingMetricTaskIDs.insert(task.id)
        
        Task { [weak self] in
            guard let self else { return }
            let points = await agentIndexService.metricHistory(roomID: task.roomID, taskID: task.taskID, limit: 20)
            state.loadingMetricTaskIDs.remove(task.id)
            state.metricHistories[task.id] = points
        }
    }
}
