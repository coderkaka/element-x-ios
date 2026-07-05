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

    private func makeViewModel(summary: RoomTaskSummary) -> (AgentTaskPanelScreenViewModel, CurrentValueSubject<RoomTaskSummary, Never>) {
        let summarySubject = CurrentValueSubject<RoomTaskSummary, Never>(summary)
        return (AgentTaskPanelScreenViewModel(summaryPublisher: summarySubject.asCurrentValuePublisher()), summarySubject)
    }
}
