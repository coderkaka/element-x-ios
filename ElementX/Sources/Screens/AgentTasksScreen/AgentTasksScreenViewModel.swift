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
                                                               kanbanGroupingMode: appSettings.agentTasksKanbanGroupingMode,
                                                               terminology: .init(scenario: appSettings.terminologyScenario),
                                                               spaceFilterOrder: appSettings.spaceFilterOrder),
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
        Publishers.CombineLatest3(agentIndexService.tasksPublisher, spaceService.spaceFilterPublisher, appSettings.selectedSpaceFilterRoomIDPublisher)
            .sink { [weak self] tasks, spaceFilters, selectedSpaceFilterRoomID in
                guard let self else { return }
                let scoped = Self.scopeToSelectedSpace(tasks: tasks, spaceFilters: spaceFilters, selectedSpaceFilterRoomID: selectedSpaceFilterRoomID)
                state.unresolvedTasks = scoped.tasks.filter { !$0.isResolved }
                state.resolvedTasks = scoped.tasks.filter(\.isResolved)
                state.kanbanColumns = Self.makeKanbanColumns(tasks: scoped.tasks, groupingMode: state.kanbanGroupingMode, terminology: state.terminology)
                state.metricTasks = scoped.tasks.filter { $0.metric != nil }
                state.selectedSpaceFilterName = scoped.filterName
                state.selectedSpaceFilterRoomID = selectedSpaceFilterRoomID
                state.availableSpaceFilters = spaceFilters
            }
            .store(in: &cancellables)

        appSettings.terminologyScenarioPublisher
            .sink { [weak self] scenario in
                guard let self else { return }
                state.terminology = .init(scenario: scenario)
                state.kanbanColumns = Self.makeKanbanColumns(tasks: state.unresolvedTasks + state.resolvedTasks,
                                                             groupingMode: state.kanbanGroupingMode,
                                                             terminology: state.terminology)
            }
            .store(in: &cancellables)

        // Keeps the 道 menu's chip order live: the coordinator/view model is created once per
        // session and outlives tab switches, so a reorder done on 政事堂 after the 差事 tab was
        // first opened must still reach `topLevelSpaceFilters` here, not just at launch.
        appSettings.spaceFilterOrderPublisher
            .sink { [weak self] order in
                self?.state.spaceFilterOrder = order
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
        case .setKanbanGroupingMode(let mode):
            appSettings.agentTasksKanbanGroupingMode = mode
            state.kanbanGroupingMode = mode
            state.kanbanColumns = Self.makeKanbanColumns(tasks: state.unresolvedTasks + state.resolvedTasks,
                                                          groupingMode: mode,
                                                          terminology: state.terminology)
        case .loadMetricHistory(let task):
            loadMetricHistory(for: task)
        case .showSettings:
            actionsSubject.send(.showSettings)
        case .selectSpaceFilter(let roomID):
            // Just writes the setting — the CombineLatest3 subscription above (which already
            // observes `selectedSpaceFilterRoomIDPublisher`) reacts and recomputes everything,
            // and `HomeScreenViewModel`'s own subscription to the same setting keeps 政事堂 in
            // sync (contract C in the fix-kanban brief).
            appSettings.selectedSpaceFilterRoomID = roomID
        }
    }
    
    // MARK: - Private

    /// Explicitly scopes the index's (always-full, see `AgentIndexService`) tasks down to the
    /// 道 currently selected on 政事堂, so the 差事 tab visibly follows that same selection
    /// rather than "coincidentally" matching whatever the home tab's room list happened to be
    /// showing. A `nil` selection, or one that doesn't match any joined 道 (space left, or the
    /// index hasn't caught up yet), means unfiltered — the second element of the tuple is the
    /// matched 道's name, `nil` when unfiltered, driving the indicator strip.
    private static func scopeToSelectedSpace(tasks: [AgentTaskSummary],
                                             spaceFilters: [SpaceServiceFilter],
                                             selectedSpaceFilterRoomID: String?) -> (tasks: [AgentTaskSummary], filterName: String?) {
        guard let selectedSpaceFilterRoomID,
              let filter = spaceFilters.first(where: { $0.room.id == selectedSpaceFilterRoomID }) else {
            return (tasks, nil)
        }
        return (tasks.filter { filter.descendants.contains($0.roomID) }, filter.room.name)
    }

    private static func makeKanbanColumns(tasks: [AgentTaskSummary],
                                          groupingMode: AgentTasksKanbanGroupingMode,
                                          terminology: AppTerminology) -> [AgentTasksKanbanColumn] {
        switch groupingMode {
        case .status: makeStatusKanbanColumns(tasks: tasks, terminology: terminology)
        case .room: makeRoomKanbanColumns(tasks: tasks)
        }
    }

    /// Two fixed columns, always both present (even empty) so the board's skeleton doesn't
    /// jump around as data streams in. `AgentTaskSummary` only carries a resolved/unresolved
    /// bool (see `AgentTaskStateEvent`, which collapses the state event's richer `status` string
    /// down to that at parse time) — no pending/in_progress split survives to this layer, hence
    /// two columns rather than three.
    private static func makeStatusKanbanColumns(tasks: [AgentTaskSummary], terminology: AppTerminology) -> [AgentTasksKanbanColumn] {
        [
            AgentTasksKanbanColumn(id: "active", title: terminology.sectionActive, tasks: tasks.filter { !$0.isResolved }),
            AgentTasksKanbanColumn(id: "done", title: terminology.sectionDone, tasks: tasks.filter(\.isResolved))
        ]
    }

    /// One column per 案(room) that has at least one task — unlike 按状态 mode, columns are
    /// data-derived so an empty task list naturally yields zero columns. Ordered by each
    /// column's most-recently-updated task descending; columns with no timestamped task (see
    /// `AgentTaskSummary.updatedAt`) sort last, ties otherwise keeping first-seen room order
    /// (`Array.sorted` is a stable sort as of Swift 5, relied on here).
    private static func makeRoomKanbanColumns(tasks: [AgentTaskSummary]) -> [AgentTasksKanbanColumn] {
        var roomOrder: [String] = []
        var tasksByRoomID: [String: [AgentTaskSummary]] = [:]
        for task in tasks {
            if tasksByRoomID[task.roomID] == nil {
                roomOrder.append(task.roomID)
            }
            tasksByRoomID[task.roomID, default: []].append(task)
        }

        let columns = roomOrder.map { roomID -> AgentTasksKanbanColumn in
            let roomTasks = tasksByRoomID[roomID] ?? []
            let title = roomTasks.first(where: { !$0.roomName.isEmpty })?.roomName ?? shortRoomID(roomID)
            return AgentTasksKanbanColumn(id: roomID, title: title, tasks: roomTasks)
        }

        return columns.sorted { lhs, rhs in
            switch (lhs.tasks.compactMap(\.updatedAt).max(), rhs.tasks.compactMap(\.updatedAt).max()) {
            case let (lhsDate?, rhsDate?): lhsDate > rhsDate
            case (nil, nil): false
            case (nil, _): false
            case (_, nil): true
            }
        }
    }

    /// `"!abc123:example.com"` → `"abc123"` — the fallback 案 column title when a room has no
    /// name (defensive; `RoomSummary.name` normally never comes back empty).
    private static func shortRoomID(_ roomID: String) -> String {
        guard let localPart = roomID.dropFirst().split(separator: ":").first, !localPart.isEmpty else {
            return roomID
        }
        return String(localPart)
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
