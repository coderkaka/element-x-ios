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
    
    // MARK: - Kanban columns (按状态, default)
    
    @Test
    func kanbanColumnsGroupByStatusByDefault() {
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, Self.resolvedTask])
        
        #expect(viewModel.context.viewState.kanbanGroupingMode == .status)
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
    
    // MARK: - Kanban columns (按案)
    
    @Test
    func kanbanColumnsGroupByRoomWhenModeIsRoom() {
        let appSettings: AppSettings = .volatile()
        appSettings.agentTasksKanbanGroupingMode = .room
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, Self.resolvedTask], appSettings: appSettings)
        
        let columns = viewModel.context.viewState.kanbanColumns
        #expect(columns.count == 2)
        #expect(columns.map(\.id).sorted() == [Self.resolvedTask.roomID, Self.unresolvedTask.roomID].sorted())
        #expect(columns.first { $0.id == Self.unresolvedTask.roomID }?.title == Self.unresolvedTask.roomName)
        #expect(columns.first { $0.id == Self.unresolvedTask.roomID }?.tasks == [Self.unresolvedTask])
    }
    
    @Test
    func kanbanRoomColumnsGroupMultipleTasksInTheSameRoomTogether() {
        let appSettings: AppSettings = .volatile()
        appSettings.agentTasksKanbanGroupingMode = .room
        let secondTaskInSameRoom = AgentTaskSummary(roomID: Self.unresolvedTask.roomID, roomName: Self.unresolvedTask.roomName,
                                                    taskID: "task-1b", title: "Second task", isResolved: true,
                                                    doneStepCount: 1, totalStepCount: 1)
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, secondTaskInSameRoom], appSettings: appSettings)
        
        let columns = viewModel.context.viewState.kanbanColumns
        #expect(columns.count == 1)
        #expect(Set(columns[0].tasks.map(\.id)) == [Self.unresolvedTask.id, secondTaskInSameRoom.id])
    }
    
    @Test
    func kanbanRoomColumnsOrderByMostRecentUpdatedAtDescending() {
        let appSettings: AppSettings = .volatile()
        appSettings.agentTasksKanbanGroupingMode = .room
        let olderTask = AgentTaskSummary(roomID: "!old:example.com", roomName: "Older room", taskID: "task-old",
                                         title: nil, isResolved: false, doneStepCount: 0, totalStepCount: 1,
                                         updatedAt: Date(timeIntervalSince1970: 1000))
        let newerTask = AgentTaskSummary(roomID: "!new:example.com", roomName: "Newer room", taskID: "task-new",
                                         title: nil, isResolved: false, doneStepCount: 0, totalStepCount: 1,
                                         updatedAt: Date(timeIntervalSince1970: 2000))
        let (viewModel, _) = makeViewModel(tasks: [olderTask, newerTask], appSettings: appSettings)
        
        #expect(viewModel.context.viewState.kanbanColumns.map(\.id) == ["!new:example.com", "!old:example.com"])
    }
    
    @Test
    func kanbanRoomColumnsWithoutTimestampsSortLastKeepingFirstSeenOrder() {
        let appSettings: AppSettings = .volatile()
        appSettings.agentTasksKanbanGroupingMode = .room
        let timestamped = AgentTaskSummary(roomID: "!timestamped:example.com", roomName: "Timestamped", taskID: "task-t",
                                           title: nil, isResolved: false, doneStepCount: 0, totalStepCount: 1,
                                           updatedAt: Date(timeIntervalSince1970: 1000))
        let firstUntimestamped = AgentTaskSummary(roomID: "!first:example.com", roomName: "First", taskID: "task-1",
                                                  title: nil, isResolved: false, doneStepCount: 0, totalStepCount: 1)
        let secondUntimestamped = AgentTaskSummary(roomID: "!second:example.com", roomName: "Second", taskID: "task-2",
                                                   title: nil, isResolved: false, doneStepCount: 0, totalStepCount: 1)
        let (viewModel, _) = makeViewModel(tasks: [firstUntimestamped, secondUntimestamped, timestamped], appSettings: appSettings)
        
        #expect(viewModel.context.viewState.kanbanColumns.map(\.id) == [
            "!timestamped:example.com", "!first:example.com", "!second:example.com"
        ])
    }
    
    @Test
    func kanbanRoomColumnsFallBackToShortRoomIDWhenNameIsEmpty() {
        let appSettings: AppSettings = .volatile()
        appSettings.agentTasksKanbanGroupingMode = .room
        let unnamed = AgentTaskSummary(roomID: "!unnamed123:example.com", roomName: "", taskID: "task-u",
                                       title: nil, isResolved: false, doneStepCount: 0, totalStepCount: 1)
        let (viewModel, _) = makeViewModel(tasks: [unnamed], appSettings: appSettings)
        
        #expect(viewModel.context.viewState.kanbanColumns.first?.title == "unnamed123")
    }
    
    // MARK: - Kanban grouping mode switch
    
    @Test
    func setKanbanGroupingModePersistsToAppSettingsAndRecomputesColumns() {
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask], appSettings: appSettings)
        
        #expect(viewModel.context.viewState.kanbanGroupingMode == .status)
        viewModel.context.send(viewAction: .setKanbanGroupingMode(.room))
        
        #expect(viewModel.context.viewState.kanbanGroupingMode == .room)
        #expect(appSettings.agentTasksKanbanGroupingMode == .room)
        #expect(viewModel.context.viewState.kanbanColumns.map(\.id) == [Self.unresolvedTask.roomID])
    }
    
    // MARK: - 道 filter menu (contract B)
    
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
    func spaceFilterMenuOrderFollowsALaterReorderOnAppSettings() {
        // The view model is created once per session and outlives switching tabs, so a 道 reorder
        // done on 政事堂 *after* the 差事 tab was first opened must still reach the 道 menu here,
        // not just whatever order was current at construction time.
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init([
            .init(room: .mock(id: "!a:example.com", name: "A", isSpace: true), level: 0, descendants: []),
            .init(room: .mock(id: "!b:example.com", name: "B", isSpace: true), level: 0, descendants: [])
        ])
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(tasks: [], spaceService: spaceService, appSettings: appSettings)
        
        #expect(viewModel.context.viewState.topLevelSpaceFilters.map(\.room.id) == ["!a:example.com", "!b:example.com"])
        
        appSettings.spaceFilterOrder = ["!b:example.com", "!a:example.com"]
        
        #expect(viewModel.context.viewState.topLevelSpaceFilters.map(\.room.id) == ["!b:example.com", "!a:example.com"])
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
                               selectedSpaceFilterRoomID: String? = nil) -> (AgentTasksScreenViewModel, CurrentValueSubject<[AgentTaskSummary], Never>) {
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
        
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@alice:example.com"))))
        return (AgentTasksScreenViewModel(userSession: userSession,
                                          agentIndexService: indexService,
                                          spaceService: resolvedSpaceService,
                                          appSettings: appSettings), tasksSubject)
    }
}
