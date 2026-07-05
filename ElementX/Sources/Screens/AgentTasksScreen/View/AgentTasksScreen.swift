//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct AgentTasksScreen: View {
    @Bindable var context: AgentTasksScreenViewModel.Context

    var body: some View {
        if context.viewState.isEmpty {
            emptyState
        } else {
            taskList
        }
    }

    private var taskList: some View {
        Form {
            if !context.viewState.unresolvedTasks.isEmpty {
                Section {
                    ForEach(context.viewState.unresolvedTasks) { task in
                        taskRow(task)
                    }
                } header: {
                    Text(UntranslatedL10n.screenAgentTasksSectionActive)
                        .compoundListSectionHeader()
                }
            }

            if !context.viewState.resolvedTasks.isEmpty {
                Section {
                    ForEach(context.viewState.resolvedTasks) { task in
                        taskRow(task)
                    }
                } header: {
                    Text(UntranslatedL10n.screenAgentTasksSectionDone)
                        .compoundListSectionHeader()
                }
            }
        }
        .compoundList()
    }

    private func taskRow(_ task: AgentTaskSummary) -> some View {
        ListRow(label: .plain(title: task.title ?? task.taskID,
                              description: task.roomName),
                details: .title("\(task.doneStepCount)/\(task.totalStepCount)"),
                kind: .button {
                    context.send(viewAction: .taskTapped(task))
                })
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            CompoundIcon(\.polls, size: .medium, relativeTo: .compound.bodyLG)
                .foregroundColor(.compound.iconSecondary)
            Text(UntranslatedL10n.screenAgentTasksEmpty)
                .font(.compound.bodyLG)
                .foregroundColor(.compound.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
    }
}

// MARK: - Previews

struct AgentTasksScreen_Previews: PreviewProvider, TestablePreview {
    static let emptyViewModel = makeViewModel(tasks: [])
    static let mixedViewModel = makeViewModel(tasks: [
        .init(roomID: "!a:example.com",
              roomName: "Backend",
              taskID: "task-1",
              title: "Refactor auth module",
              isResolved: false,
              doneStepCount: 1,
              totalStepCount: 3),
        .init(roomID: "!b:example.com",
              roomName: "iOS App",
              taskID: "task-2",
              title: nil,
              isResolved: false,
              doneStepCount: 0,
              totalStepCount: 2),
        .init(roomID: "!c:example.com",
              roomName: "Docs",
              taskID: "task-3",
              title: "Write release notes",
              isResolved: true,
              doneStepCount: 2,
              totalStepCount: 2)
    ])
    static let allDoneViewModel = makeViewModel(tasks: [
        .init(roomID: "!a:example.com",
              roomName: "Backend",
              taskID: "task-1",
              title: "Refactor auth module",
              isResolved: true,
              doneStepCount: 3,
              totalStepCount: 3)
    ])

    static var previews: some View {
        ElementNavigationStack {
            AgentTasksScreen(context: emptyViewModel.context)
        }
        .previewDisplayName("Empty")

        ElementNavigationStack {
            AgentTasksScreen(context: mixedViewModel.context)
        }
        .previewDisplayName("Mixed")

        ElementNavigationStack {
            AgentTasksScreen(context: allDoneViewModel.context)
        }
        .previewDisplayName("All done")
    }

    static func makeViewModel(tasks: [AgentTaskSummary]) -> AgentTasksScreenViewModel {
        let indexService = AgentTaskIndexServiceMock()
        indexService.underlyingTasksPublisher = .init(tasks)
        return AgentTasksScreenViewModel(agentTaskIndexService: indexService)
    }
}
