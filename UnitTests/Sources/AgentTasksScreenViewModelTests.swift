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
    
    private func makeViewModel(tasks: [AgentTaskSummary]) -> (AgentTasksScreenViewModel, CurrentValueSubject<[AgentTaskSummary], Never>) {
        let tasksSubject = CurrentValueSubject<[AgentTaskSummary], Never>(tasks)
        let indexService = AgentTaskIndexServiceMock()
        indexService.underlyingTasksPublisher = tasksSubject.asCurrentValuePublisher()
        return (AgentTasksScreenViewModel(agentTaskIndexService: indexService, appSettings: .volatile()), tasksSubject)
    }
}
