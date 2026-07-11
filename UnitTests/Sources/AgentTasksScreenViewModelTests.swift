//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
import Testing

@MainActor
struct AgentTasksScreenViewModelTests {
    @Test
    func initialStateSplitsTasksByResolution() {
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, Self.resolvedTask])
        
        #expect(viewModel.context.viewState.unresolvedTasks == [Self.unresolvedTask])
        #expect(viewModel.context.viewState.resolvedTasks == [Self.resolvedTask])
        #expect(!viewModel.context.viewState.isEmpty)
    }
    
    @Test
    func emptyServiceGivesEmptyState() {
        let (viewModel, _) = makeViewModel(tasks: [])
        
        #expect(viewModel.context.viewState.isEmpty)
    }
    
    @Test
    func publisherUpdatesAreReflectedInState() async throws {
        let (viewModel, tasksSubject) = makeViewModel(tasks: [])
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.unresolvedTasks)) { !$0.isEmpty }
        tasksSubject.send([Self.unresolvedTask, Self.resolvedTask])
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.unresolvedTasks == [Self.unresolvedTask])
        #expect(viewModel.context.viewState.resolvedTasks == [Self.resolvedTask])
    }
    
    @Test
    func tappingTaskPresentsItsCanvasSteps() async throws {
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask])
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            action == .presentCanvasSteps(roomID: Self.unresolvedTask.roomID, taskID: Self.unresolvedTask.taskID)
        }
        viewModel.context.send(viewAction: .taskTapped(Self.unresolvedTask))
        try await deferred.fulfill()
    }
    
    @Test
    func showSettingsForwardsTheAction() async throws {
        let (viewModel, _) = makeViewModel(tasks: [])
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .showSettings }
        viewModel.context.send(viewAction: .showSettings)
        try await deferred.fulfill()
    }
    
    @Test
    func setViewModePersistsToAppSettings() {
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(tasks: [], appSettings: appSettings)
        
        #expect(viewModel.context.viewState.viewMode == .list)
        viewModel.context.send(viewAction: .setViewMode(.metric))
        #expect(viewModel.context.viewState.viewMode == .metric)
        #expect(appSettings.agentTasksViewMode == .metric)
    }
    
    @Test
    func metricTasksFiltersToTasksWithAMetric() {
        let taskWithMetric = AgentTaskSummary(roomID: "!c:example.com", roomName: "Room C", taskID: "task-3",
                                              title: "Score improvement", isResolved: false, doneStepCount: 0, totalStepCount: 1,
                                              metric: .init(current: 100, target: 130, unit: "分"))
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, taskWithMetric])
        
        #expect(viewModel.context.viewState.metricTasks == [taskWithMetric])
    }
    
    @Test
    func loadMetricHistoryFetchesAndCachesPoints() async throws {
        let taskWithMetric = AgentTaskSummary(roomID: "!c:example.com", roomName: "Room C", taskID: "task-3",
                                              title: "Score improvement", isResolved: false, doneStepCount: 0, totalStepCount: 1,
                                              metric: .init(current: 100, target: 130, unit: "分"))
        let points = [AgentTaskMetricHistoryPoint(metric: .init(current: 90, target: 130, unit: "分"), date: .now)]
        let indexService = AgentIndexServiceMock()
        indexService.underlyingTasksPublisher = .init([taskWithMetric])
        indexService.metricHistoryRoomIDTaskIDLimitClosure = { _, _, _ in points }
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init([])
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@alice:example.com"))))
        let viewModel = AgentTasksScreenViewModel(userSession: userSession,
                                                  agentIndexService: indexService,
                                                  spaceService: spaceService,
                                                  appSettings: .volatile())
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.metricHistories)) { !$0.isEmpty }
        viewModel.context.send(viewAction: .loadMetricHistory(taskWithMetric))
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.metricHistories[taskWithMetric.id] == points)
    }
    
    // MARK: - Kanban columns (按状态, the only mode — contract A drops 按案 grouping)
    
    @Test
    func kanbanColumnsGroupByStatus() {
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, Self.resolvedTask])
        
        #expect(viewModel.context.viewState.kanbanColumns.count == 2)
        #expect(viewModel.context.viewState.kanbanColumns[0].tasks == [Self.unresolvedTask])
        #expect(viewModel.context.viewState.kanbanColumns[1].tasks == [Self.resolvedTask])
    }
    
    @Test
    func kanbanStatusColumnsAreAlwaysPresentEvenWhenEmpty() {
        // The board's column skeleton shouldn't jump around as data streams in — both status
        // columns must exist even with zero tasks in them.
        let (viewModel, _) = makeViewModel(tasks: [])
        
        #expect(viewModel.context.viewState.kanbanColumns.count == 2)
        #expect(!viewModel.context.viewState.kanbanColumns.contains { !$0.tasks.isEmpty })
    }
    
    // MARK: - 道条(contract B): chip selection
    
    @Test
    func selectSpaceFilterWritesTheRoomIDToAppSettings() {
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(tasks: [], appSettings: appSettings)
        
        viewModel.context.send(viewAction: .selectSpaceFilter("!space:example.com"))
        
        #expect(appSettings.selectedSpaceFilterRoomID == "!space:example.com")
    }
    
    @Test
    func selectingAllClearsTheAppSettingsSelection() {
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(tasks: [], appSettings: appSettings, selectedSpaceFilterRoomID: "!space:example.com")
        
        viewModel.context.send(viewAction: .selectSpaceFilter(nil))
        
        #expect(appSettings.selectedSpaceFilterRoomID == nil)
    }
    
    @Test
    func navigationTitleShowsTheSelectedSpaceNameOtherwiseTheTabTitle() {
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(tasks: [], appSettings: appSettings)
        #expect(viewModel.context.viewState.navigationTitle == AppTerminology(scenario: appSettings.terminologyScenario).tabTasks)
        
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init([
            .init(room: .mock(id: "!a:example.com", name: "工程院", isSpace: true), level: 0, descendants: [])
        ])
        let (filteredViewModel, _) = makeViewModel(tasks: [], spaceService: spaceService, selectedSpaceFilterRoomID: "!a:example.com")
        #expect(filteredViewModel.context.viewState.navigationTitle == "工程院")
    }
    
    // MARK: - 道 picker panel (fix-spacebar3 contract B)
    
    @Test
    func spaceFiltersActionPresentsThePanel() {
        let (viewModel, _) = makeViewModel(tasks: [])
        #expect(viewModel.context.viewState.bindings.spaceFiltersViewModel == nil)
        
        viewModel.context.send(viewAction: .spaceFilters)
        #expect(viewModel.context.viewState.bindings.spaceFiltersViewModel != nil)
    }
    
    @Test
    func confirmingAFilterInThePanelWritesTheSettingAndDismissesIt() async throws {
        let filter = SpaceServiceFilter(room: .mock(id: "!a:example.com", name: "工程院", isSpace: true), level: 0, descendants: [])
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init([filter])
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(tasks: [], spaceService: spaceService, appSettings: appSettings)
        
        viewModel.context.send(viewAction: .spaceFilters)
        let panel = try #require(viewModel.context.viewState.bindings.spaceFiltersViewModel)
        
        panel.context.send(viewAction: .confirm(filter))
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(appSettings.selectedSpaceFilterRoomID == "!a:example.com")
        #expect(viewModel.context.viewState.bindings.spaceFiltersViewModel == nil)
    }
    
    @Test
    func manageSpacesFromThePanelForwardsShowSpaceManagementAndDismissesIt() async throws {
        let (viewModel, _) = makeViewModel(tasks: [])
        viewModel.context.send(viewAction: .spaceFilters)
        let panel = try #require(viewModel.context.viewState.bindings.spaceFiltersViewModel)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .showSpaceManagement }
        panel.context.send(viewAction: .manageSpaces)
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.bindings.spaceFiltersViewModel == nil)
    }
    
    /// The panel is a SwiftUI `.sheet(item:)` — presenting another sheet straight after nil-ing
    /// the binding (same run loop tick) silently drops because the panel's dismiss animation
    /// hasn't finished yet. `.showSpaceManagement` must only fire once that dismissal has had
    /// time to complete. Mirrors `HomeScreenViewModelTests`' identical case.
    @Test
    func manageSpacesFromThePanelDelaysShowSpaceManagementUntilTheSheetHasDismissed() async throws {
        let (viewModel, _) = makeViewModel(tasks: [])
        viewModel.context.send(viewAction: .spaceFilters)
        let panel = try #require(viewModel.context.viewState.bindings.spaceFiltersViewModel)
        
        var cancellables = Set<AnyCancellable>()
        var receivedAction = false
        viewModel.actionsPublisher.sink { action in
            if action == .showSpaceManagement {
                receivedAction = true
            }
        }
        .store(in: &cancellables)
        
        panel.context.send(viewAction: .manageSpaces)
        #expect(!receivedAction, "showSpaceManagement must not fire synchronously with the dismissal")
        
        try await Task.sleep(for: .milliseconds(200))
        #expect(receivedAction)
    }
    
    @Test
    func manageSpacesForwardsShowSpaceManagementAction() async throws {
        let (viewModel, _) = makeViewModel(tasks: [])
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .showSpaceManagement }
        viewModel.context.send(viewAction: .manageSpaces)
        try await deferred.fulfill()
    }
    
    // MARK: - 受邀红点(contract B)
    
    @Test
    func hasPendingSpaceInvitesReflectsAnUnseenSpaceInvite() {
        let clientProxy = ClientProxyMock(.init(userID: "@alice:example.com"))
        clientProxy.staticRoomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded(.mockSpaceInvites)))
        let (viewModel, _) = makeViewModel(tasks: [], clientProxy: clientProxy)
        
        #expect(viewModel.context.viewState.hasPendingSpaceInvites)
    }
    
    @Test
    func hasPendingSpaceInvitesIsFalseOnceSeen() {
        let clientProxy = ClientProxyMock(.init(userID: "@alice:example.com"))
        clientProxy.staticRoomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded(.mockSpaceInvites)))
        let appSettings: AppSettings = .volatile()
        appSettings.seenInvites = Set([RoomSummary].mockSpaceInvites.map(\.id))
        let (viewModel, _) = makeViewModel(tasks: [], appSettings: appSettings, clientProxy: clientProxy)
        
        #expect(!viewModel.context.viewState.hasPendingSpaceInvites)
    }
    
    @Test
    func hasPendingSpaceInvitesIsFalseWithNoInvites() {
        let (viewModel, _) = makeViewModel(tasks: [])
        
        #expect(!viewModel.context.viewState.hasPendingSpaceInvites)
    }
    
    // MARK: - 道 filter following
    
    @Test
    func selectedSpaceScopesTasksToItsDescendantsAndSurfacesItsName() {
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init([
            .init(room: .mock(id: "!space:example.com", name: "工程院", isSpace: true), level: 0, descendants: [Self.unresolvedTask.roomID])
        ])
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, Self.resolvedTask],
                                           spaceService: spaceService,
                                           selectedSpaceFilterRoomID: "!space:example.com")
        
        #expect(viewModel.context.viewState.unresolvedTasks == [Self.unresolvedTask])
        #expect(viewModel.context.viewState.resolvedTasks == [])
        #expect(viewModel.context.viewState.selectedSpaceFilterName == "工程院")
    }
    
    @Test
    func noSelectedSpaceShowsEverythingUnfiltered() {
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init([
            .init(room: .mock(id: "!space:example.com", name: "工程院", isSpace: true), level: 0, descendants: [Self.unresolvedTask.roomID])
        ])
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, Self.resolvedTask],
                                           spaceService: spaceService,
                                           selectedSpaceFilterRoomID: nil)
        
        #expect(viewModel.context.viewState.unresolvedTasks == [Self.unresolvedTask])
        #expect(viewModel.context.viewState.resolvedTasks == [Self.resolvedTask])
        #expect(viewModel.context.viewState.selectedSpaceFilterName == nil)
    }
    
    @Test
    func unknownSelectedSpaceRoomIDFallsBackToUnfiltered() {
        // The persisted selection can point at a 道 that's no longer in `spaceFilterPublisher`
        // (e.g. the space was left) — that must read as "unfiltered", not "show nothing".
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init([
            .init(room: .mock(id: "!space:example.com", name: "工程院", isSpace: true), level: 0, descendants: [Self.unresolvedTask.roomID])
        ])
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, Self.resolvedTask],
                                           spaceService: spaceService,
                                           selectedSpaceFilterRoomID: "!no-longer-joined:example.com")
        
        #expect(viewModel.context.viewState.unresolvedTasks == [Self.unresolvedTask])
        #expect(viewModel.context.viewState.resolvedTasks == [Self.resolvedTask])
        #expect(viewModel.context.viewState.selectedSpaceFilterName == nil)
    }
    
    @Test
    func selectedSpaceAlsoScopesKanbanAndMetricTasks() {
        let taskWithMetric = AgentTaskSummary(roomID: "!c:example.com", roomName: "Room C", taskID: "task-3",
                                              title: "Score improvement", isResolved: false, doneStepCount: 0, totalStepCount: 1,
                                              metric: .init(current: 100, target: 130, unit: "分"))
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init([
            .init(room: .mock(id: "!space:example.com", name: "工程院", isSpace: true), level: 0, descendants: [Self.unresolvedTask.roomID])
        ])
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, taskWithMetric],
                                           spaceService: spaceService,
                                           selectedSpaceFilterRoomID: "!space:example.com")
        
        #expect(viewModel.context.viewState.kanbanColumns.map(\.tasks) == [[Self.unresolvedTask], []])
        #expect(viewModel.context.viewState.metricTasks == [])
    }
    
    // MARK: - Helpers
    
    private static let unresolvedTask = AgentTaskSummary(roomID: "!a:example.com",
                                                         roomName: "Room A",
                                                         taskID: "task-1",
                                                         title: "Refactor auth module",
                                                         isResolved: false,
                                                         doneStepCount: 1,
                                                         totalStepCount: 3)
    
    private static let resolvedTask = AgentTaskSummary(roomID: "!b:example.com",
                                                       roomName: "Room B",
                                                       taskID: "task-2",
                                                       title: nil,
                                                       isResolved: true,
                                                       doneStepCount: 2,
                                                       totalStepCount: 2)
    
    private func makeViewModel(tasks: [AgentTaskSummary],
                               spaceService: SpaceServiceProxyProtocol? = nil,
                               appSettings: AppSettings = .volatile(),
                               selectedSpaceFilterRoomID: String? = nil,
                               clientProxy: ClientProxyMock? = nil) -> (AgentTasksScreenViewModel, CurrentValueSubject<[AgentTaskSummary], Never>) {
        appSettings.selectedSpaceFilterRoomID = selectedSpaceFilterRoomID
        let tasksSubject = CurrentValueSubject<[AgentTaskSummary], Never>(tasks)
        let indexService = AgentIndexServiceMock()
        indexService.underlyingTasksPublisher = tasksSubject.asCurrentValuePublisher()
        
        let resolvedSpaceService: SpaceServiceProxyProtocol
        if let spaceService {
            resolvedSpaceService = spaceService
        } else {
            let mock = SpaceServiceProxyMock()
            mock.underlyingSpaceFilterPublisher = .init([])
            resolvedSpaceService = mock
        }
        
        let resolvedClientProxy = clientProxy ?? ClientProxyMock(.init(userID: "@alice:example.com"))
        let userSession = UserSessionMock(.init(clientProxy: resolvedClientProxy))
        return (AgentTasksScreenViewModel(userSession: userSession,
                                          agentIndexService: indexService,
                                          spaceService: resolvedSpaceService,
                                          appSettings: appSettings), tasksSubject)
    }
}
