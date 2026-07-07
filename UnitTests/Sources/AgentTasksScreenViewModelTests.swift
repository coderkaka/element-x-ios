//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
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
    func toggleViewModePersistsToAppSettings() {
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(tasks: [], appSettings: appSettings)
        
        #expect(!viewModel.context.viewState.isKanbanViewEnabled)
        viewModel.context.send(viewAction: .toggleViewMode)
        #expect(viewModel.context.viewState.isKanbanViewEnabled)
        #expect(appSettings.agentTasksKanbanViewEnabled)
    }
    
    @Test
    func kanbanColumnsGroupTasksBySpaceAndFallBackForUnassignedRooms() {
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init([
            .init(room: .mock(id: "!space:example.com", name: "工程院", isSpace: true), level: 0, descendants: [Self.unresolvedTask.roomID])
        ])
        let (viewModel, _) = makeViewModel(tasks: [Self.unresolvedTask, Self.resolvedTask], spaceService: spaceService)
        
        #expect(viewModel.context.viewState.kanbanColumns.count == 2)
        #expect(viewModel.context.viewState.kanbanColumns[0].title == "工程院")
        #expect(viewModel.context.viewState.kanbanColumns[0].tasks == [Self.unresolvedTask])
        #expect(viewModel.context.viewState.kanbanColumns[1].tasks == [Self.resolvedTask])
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
                               appSettings: AppSettings = .volatile()) -> (AgentTasksScreenViewModel, CurrentValueSubject<[AgentTaskSummary], Never>) {
        let tasksSubject = CurrentValueSubject<[AgentTaskSummary], Never>(tasks)
        let indexService = AgentTaskIndexServiceMock()
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
                                          agentTaskIndexService: indexService,
                                          spaceService: resolvedSpaceService,
                                          appSettings: appSettings), tasksSubject)
    }
}
