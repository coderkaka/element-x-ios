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
struct AgentTaskPanelScreenViewModelTests {
    @Test
    func initialStateSplitsSummary() {
        let (viewModel, _) = makeViewModel(summary: Self.mixedSummary)
        
        #expect(viewModel.context.viewState.pendingChoices == Self.mixedSummary.pendingChoices)
        #expect(viewModel.context.viewState.activeTasks == Self.mixedSummary.activeTasks)
        #expect(viewModel.context.viewState.doneTasks == Self.mixedSummary.doneTasks)
        #expect(!viewModel.context.viewState.isEmpty)
    }
    
    @Test
    func emptySummaryGivesEmptyState() {
        let (viewModel, _) = makeViewModel(summary: RoomTaskSummary())
        
        #expect(viewModel.context.viewState.isEmpty)
    }
    
    @Test
    func publisherUpdatesAreReflectedInState() async throws {
        let (viewModel, summarySubject) = makeViewModel(summary: RoomTaskSummary())
        
        #expect(viewModel.context.viewState.isEmpty)
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.activeTasks)) { !$0.isEmpty }
        summarySubject.send(Self.mixedSummary)
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.pendingChoices == Self.mixedSummary.pendingChoices)
        #expect(viewModel.context.viewState.activeTasks == Self.mixedSummary.activeTasks)
        #expect(viewModel.context.viewState.doneTasks == Self.mixedSummary.doneTasks)
    }
    
    @Test
    func tappingTaskPresentsItsDetail() async throws {
        let (viewModel, _) = makeViewModel(summary: Self.mixedSummary)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            action == .presentTaskDetail(task: Self.activeTask)
        }
        viewModel.context.send(viewAction: .taskTapped(Self.activeTask))
        try await deferred.fulfill()
    }
    
    @Test
    func tappingChoiceFocusesItsTimelineEvent() async throws {
        let (viewModel, _) = makeViewModel(summary: Self.mixedSummary)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            action == .focusTimelineEvent(eventID: Self.pendingChoice.eventID)
        }
        viewModel.context.send(viewAction: .choiceTapped(eventID: Self.pendingChoice.eventID))
        try await deferred.fulfill()
    }
    
    // MARK: - Objective grouping
    
    @Test
    func objectiveSectionsGroupActiveTasksAndKeepEmptyActiveObjectives() {
        let taggedTask = Self.task(taskID: "t1", objectiveID: "obj-1")
        let (viewModel, _) = makeViewModel(summary: RoomTaskSummary(activeTasks: [taggedTask],
                                                                    objectives: [Self.objective(id: "obj-1"),
                                                                                 Self.objective(id: "obj-empty")]))
        let sections = viewModel.context.viewState.objectiveSections
        #expect(sections.count == 2)
        #expect(sections.first { $0.id == "obj-1" }?.tasks == [taggedTask])
        #expect(sections.first { $0.id == "obj-empty" }?.tasks.isEmpty == true)
    }
    
    @Test
    func doneAndAbandonedObjectivesDoNotGetSections() {
        let (viewModel, _) = makeViewModel(summary: RoomTaskSummary(objectives: [Self.objective(id: "a", status: .done),
                                                                                 Self.objective(id: "b", status: .abandoned),
                                                                                 Self.objective(id: "c", status: .active)]))
        #expect(viewModel.context.viewState.objectiveSections.map(\.id) == ["c"])
    }
    
    @Test
    func ungroupedActiveTasksExcludeThoseUnderActiveObjectives() {
        let underActive = Self.task(taskID: "t1", objectiveID: "obj-active")
        let underDone = Self.task(taskID: "t2", objectiveID: "obj-done")
        let unowned = Self.task(taskID: "t3", objectiveID: nil)
        let (viewModel, _) = makeViewModel(summary: RoomTaskSummary(activeTasks: [underActive, underDone, unowned],
                                                                    objectives: [Self.objective(id: "obj-active", status: .active),
                                                                                 Self.objective(id: "obj-done", status: .done)]))
        // Under a done objective → ungrouped (no section for it); unowned → ungrouped; under active → grouped only.
        #expect(viewModel.context.viewState.ungroupedActiveTasks.map(\.taskID) == ["t2", "t3"])
    }
    
    @Test
    func objectiveSectionsSortByUpdatedAtThenIDForDeterminism() {
        let epoch = Date(timeIntervalSince1970: 0)
        let (viewModel, _) = makeViewModel(summary: RoomTaskSummary(objectives: [
            Self.objective(id: "b-older", updatedAt: epoch),
            Self.objective(id: "a-older", updatedAt: epoch), // equal timestamp → tie-break on id
            Self.objective(id: "z-newest", updatedAt: epoch.addingTimeInterval(100))
        ]))
        // Newest first; equal timestamps ordered by objectiveID ascending.
        #expect(viewModel.context.viewState.objectiveSections.map(\.id) == ["z-newest", "a-older", "b-older"])
    }
    
    // MARK: - Helpers
    
    private static let activeTask = RoomTaskSummary.Task(eventID: "$task-1",
                                                         taskID: "task-1",
                                                         title: "Refactor auth module",
                                                         isResolved: false,
                                                         doneStepCount: 1,
                                                         totalStepCount: 3,
                                                         steps: [],
                                                         threadRootEventID: nil,
                                                         updatedAt: nil)
    
    private static let doneTask = RoomTaskSummary.Task(eventID: "$task-2",
                                                       taskID: "task-2",
                                                       title: "Update dependencies",
                                                       isResolved: true,
                                                       doneStepCount: 2,
                                                       totalStepCount: 2,
                                                       steps: [],
                                                       threadRootEventID: nil,
                                                       updatedAt: nil)
    
    private static let pendingChoice = RoomTaskSummary.PendingChoice(eventID: "$choice-1",
                                                                     question: "Deploy to staging first?")
    
    private static let mixedSummary = RoomTaskSummary(activeTasks: [activeTask],
                                                      doneTasks: [doneTask],
                                                      pendingChoices: [pendingChoice])
    
    private static func task(taskID: String, objectiveID: String?) -> RoomTaskSummary.Task {
        RoomTaskSummary.Task(eventID: "$\(taskID)", taskID: taskID, title: taskID, isResolved: false,
                             doneStepCount: 0, totalStepCount: 1, steps: [], threadRootEventID: nil, updatedAt: nil, objectiveID: objectiveID)
    }
    
    private static func objective(id: String, status: AgentObjectiveStatus = .active, updatedAt: Date = .now) -> RoomTaskSummary.Objective {
        RoomTaskSummary.Objective(objectiveID: id, title: id, status: status, successMetrics: [], exitOptions: [], priority: 0, updatedAt: updatedAt)
    }
    
    private func makeViewModel(summary: RoomTaskSummary) -> (AgentTaskPanelScreenViewModel, CurrentValueSubject<RoomTaskSummary, Never>) {
        let summarySubject = CurrentValueSubject<RoomTaskSummary, Never>(summary)
        return (AgentTaskPanelScreenViewModel(summaryPublisher: summarySubject.asCurrentValuePublisher(), appSettings: .volatile()), summarySubject)
    }
}
