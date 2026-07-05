//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SwiftUI

struct AgentTaskPanelScreen: View {
    @Bindable var context: AgentTaskPanelScreenViewModel.Context
    
    var body: some View {
        content
            .navigationTitle(UntranslatedL10n.screenTaskPanelTitle)
            .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private var content: some View {
        if context.viewState.isEmpty {
            emptyState
        } else {
            panelList
        }
    }
    
    private var panelList: some View {
        Form {
            if !context.viewState.pendingChoices.isEmpty {
                Section {
                    ForEach(context.viewState.pendingChoices) { choice in
                        ListRow(label: .plain(title: choice.question),
                                kind: .button {
                                    context.send(viewAction: .choiceTapped(eventID: choice.eventID))
                                })
                    }
                } header: {
                    Text(UntranslatedL10n.screenTaskPanelSectionPending)
                        .compoundListSectionHeader()
                }
            }
            
            if !context.viewState.activeTasks.isEmpty {
                Section {
                    ForEach(context.viewState.activeTasks) { task in
                        taskRow(task)
                    }
                } header: {
                    Text(UntranslatedL10n.screenTaskPanelSectionActive)
                        .compoundListSectionHeader()
                }
            }
            
            if !context.viewState.doneTasks.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(context.viewState.doneTasks) { task in
                            taskRow(task)
                        }
                    } label: {
                        Text(UntranslatedL10n.screenTaskPanelSectionDone)
                            .font(.compound.bodyLG)
                            .foregroundColor(.compound.textPrimary)
                    }
                }
            }
        }
        .compoundList()
    }
    
    private func taskRow(_ task: RoomTaskSummary.Task) -> some View {
        ListRow(label: .plain(title: task.title),
                details: .title("\(task.doneStepCount)/\(task.totalStepCount)"),
                kind: .button {
                    context.send(viewAction: .taskTapped(task))
                })
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            CompoundIcon(\.polls, size: .medium, relativeTo: .compound.bodyLG)
                .foregroundColor(.compound.iconSecondary)
                .accessibilityHidden(true)
            Text(UntranslatedL10n.screenTaskPanelEmpty)
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

struct AgentTaskPanelScreen_Previews: PreviewProvider, TestablePreview {
    static let emptyViewModel = makeViewModel(summary: RoomTaskSummary())
    static let mixedViewModel = makeViewModel(summary: mixedSummary)
    static let pendingOnlyViewModel = makeViewModel(summary: RoomTaskSummary(pendingChoices: [
        .init(eventID: "$choice-1", question: "Deploy to staging first?")
    ]))
    
    static var previews: some View {
        ElementNavigationStack {
            AgentTaskPanelScreen(context: mixedViewModel.context)
        }
        .previewDisplayName("Mixed")
        
        ElementNavigationStack {
            AgentTaskPanelScreen(context: emptyViewModel.context)
        }
        .previewDisplayName("Empty")
        
        ElementNavigationStack {
            AgentTaskPanelScreen(context: pendingOnlyViewModel.context)
        }
        .previewDisplayName("Pending only")
    }
    
    static var mixedSummary: RoomTaskSummary {
        RoomTaskSummary(activeTasks: [
            .init(eventID: "$task-1",
                  taskID: "task-1",
                  title: "Refactor auth module",
                  isResolved: false,
                  doneStepCount: 1,
                  totalStepCount: 3,
                  steps: [],
                  threadRootEventID: nil,
                  updatedAt: nil),
            .init(eventID: "$task-2",
                  taskID: "task-2",
                  title: "Ship release notes",
                  isResolved: false,
                  doneStepCount: 0,
                  totalStepCount: 2,
                  steps: [],
                  threadRootEventID: nil,
                  updatedAt: nil)
        ],
        doneTasks: [
            .init(eventID: "$task-3",
                  taskID: "task-3",
                  title: "Update dependencies",
                  isResolved: true,
                  doneStepCount: 2,
                  totalStepCount: 2,
                  steps: [],
                  threadRootEventID: nil,
                  updatedAt: nil)
        ],
        pendingChoices: [
            .init(eventID: "$choice-1", question: "Deploy to staging first?")
        ])
    }
    
    static func makeViewModel(summary: RoomTaskSummary) -> AgentTaskPanelScreenViewModel {
        AgentTaskPanelScreenViewModel(summaryPublisher: CurrentValueSubject<RoomTaskSummary, Never>(summary).asCurrentValuePublisher())
    }
}
