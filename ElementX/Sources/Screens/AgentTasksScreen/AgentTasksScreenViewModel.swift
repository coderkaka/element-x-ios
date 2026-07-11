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
    private let spaceService: SpaceServiceProxyProtocol
    private let mediaProvider: MediaProviderProtocol
    /// Unfiltered room list, used exactly like `HomeScreenViewModel`'s own copy — detecting a
    /// pending 道 invite regardless of whichever 道 filter happens to be selected right now.
    private let staticRoomSummaryProvider: StaticRoomSummaryProviderProtocol?
    
    init(userSession: UserSessionProtocol,
         agentIndexService: AgentIndexServiceProtocol,
         spaceService: SpaceServiceProxyProtocol,
         appSettings: AppSettings) {
        self.appSettings = appSettings
        self.agentIndexService = agentIndexService
        self.spaceService = spaceService
        mediaProvider = userSession.mediaProvider
        staticRoomSummaryProvider = userSession.clientProxy.staticRoomSummaryProvider
        super.init(initialViewState: AgentTasksScreenViewState(userID: userSession.clientProxy.userID,
                                                               viewMode: appSettings.agentTasksViewMode,
                                                               terminology: .init(scenario: appSettings.terminologyScenario),
                                                               bindings: .init()),
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
                state.kanbanColumns = Self.makeKanbanColumns(tasks: scoped.tasks, terminology: state.terminology)
                state.metricTasks = scoped.tasks.filter { $0.metric != nil }
                state.selectedSpaceFilterName = scoped.filterName
            }
            .store(in: &cancellables)
        
        appSettings.terminologyScenarioPublisher
            .sink { [weak self] scenario in
                guard let self else { return }
                state.terminology = .init(scenario: scenario)
                state.kanbanColumns = Self.makeKanbanColumns(tasks: state.unresolvedTasks + state.resolvedTasks, terminology: state.terminology)
            }
            .store(in: &cancellables)
        
        appSettings.seenInvitesPublisher
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updatePendingSpaceInvites()
            }
            .store(in: &cancellables)
        
        staticRoomSummaryProvider?.roomListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePendingSpaceInvites()
            }
            .store(in: &cancellables)
        
        updatePendingSpaceInvites()
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
        case .selectSpaceFilter(let roomID):
            // Just writes the setting — the CombineLatest3 subscription above (which already
            // observes `selectedSpaceFilterRoomIDPublisher`) reacts and recomputes everything,
            // and `HomeScreenViewModel`'s own subscription to the same setting keeps 政事堂 in
            // sync (contract B in the fix-kanban2 brief).
            appSettings.selectedSpaceFilterRoomID = roomID
        case .spaceFilters:
            presentSpaceFiltersSheet()
        case .manageSpaces:
            actionsSubject.send(.showSpaceManagement)
        }
    }
    
    // MARK: - Private
    
    /// Explicitly scopes the index's (always-full, see `AgentIndexService`) tasks down to the
    /// 道 currently selected on 政事堂, so the 差事 tab visibly follows that same selection
    /// rather than "coincidentally" matching whatever the home tab's room list happened to be
    /// showing. A `nil` selection, or one that doesn't match any joined 道 (space left, or the
    /// index hasn't caught up yet), means unfiltered — the second element of the tuple is the
    /// matched 道's name, `nil` when unfiltered.
    private static func scopeToSelectedSpace(tasks: [AgentTaskSummary],
                                             spaceFilters: [SpaceServiceFilter],
                                             selectedSpaceFilterRoomID: String?) -> (tasks: [AgentTaskSummary], filterName: String?) {
        guard let selectedSpaceFilterRoomID,
              let filter = spaceFilters.first(where: { $0.room.id == selectedSpaceFilterRoomID }) else {
            return (tasks, nil)
        }
        return (tasks.filter { filter.descendants.contains($0.roomID) }, filter.room.name)
    }
    
    /// Two fixed columns, always both present (even empty) so the board's skeleton doesn't
    /// jump around as data streams in. `AgentTaskSummary` only carries a resolved/unresolved
    /// bool (see `AgentTaskStateEvent`, which collapses the state event's richer `status` string
    /// down to that at parse time) — no pending/in_progress split survives to this layer, hence
    /// two columns rather than three.
    private static func makeKanbanColumns(tasks: [AgentTaskSummary], terminology: AppTerminology) -> [AgentTasksKanbanColumn] {
        [
            AgentTasksKanbanColumn(id: "active", title: terminology.sectionActive, tasks: tasks.filter { !$0.isResolved }),
            AgentTasksKanbanColumn(id: "done", title: terminology.sectionDone, tasks: tasks.filter(\.isResolved))
        ]
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
    
    /// Constructs and presents the 道 picker panel — the same screen/action shape 政事堂 uses
    /// (fix-spacebar3 contract B).
    private func presentSpaceFiltersSheet() {
        let spaceFiltersViewModel = ChatsSpaceFiltersScreenViewModel(spaceService: spaceService,
                                                                     appSettings: appSettings,
                                                                     hasPendingSpaceInvites: state.hasPendingSpaceInvites,
                                                                     mediaProvider: mediaProvider)
        
        spaceFiltersViewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .confirm(let filter):
                process(viewAction: .selectSpaceFilter(filter?.room.id))
                state.bindings.spaceFiltersViewModel = nil
            case .manageSpaces:
                state.bindings.spaceFiltersViewModel = nil
                actionsSubject.send(.showSpaceManagement)
            case .cancel:
                state.bindings.spaceFiltersViewModel = nil
            }
        }
        .store(in: &cancellables)
        
        state.bindings.spaceFiltersViewModel = spaceFiltersViewModel
    }
    
    private func updatePendingSpaceInvites() {
        guard let staticRoomSummaryProvider else { return }
        state.hasPendingSpaceInvites = hasPendingSpaceInvite(in: staticRoomSummaryProvider.roomListPublisher.value,
                                                             seenInvites: appSettings.seenInvites)
    }
}
