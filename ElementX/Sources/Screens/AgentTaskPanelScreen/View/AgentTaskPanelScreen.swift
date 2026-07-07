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
            .navigationTitle(context.viewState.terminology.taskPanelTitle)
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
                    Text(context.viewState.terminology.sectionPending)
                        .compoundListSectionHeader()
                }
            }
            
            ForEach(context.viewState.objectiveSections) { section in
                objectiveSection(section)
            }
            
            if !context.viewState.ungroupedActiveTasks.isEmpty {
                Section {
                    ForEach(context.viewState.ungroupedActiveTasks) { task in
                        taskRow(task)
                    }
                } header: {
                    // Only call it out as "ungrouped" when there are objective sections to
                    // contrast against; otherwise it's just the ordinary 在办 list.
                    Text(context.viewState.objectiveSections.isEmpty ? context.viewState.terminology.sectionActive : context.viewState.terminology.objectiveUngrouped)
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
                        Text(context.viewState.terminology.sectionDone)
                            .font(.compound.bodyLG)
                            .foregroundColor(.compound.textPrimary)
                    }
                }
            }
        }
        .compoundList()
    }
    
    private func objectiveSection(_ section: AgentTaskPanelObjectiveSection) -> some View {
        Section {
            if !section.objective.successMetrics.isEmpty {
                readOnlyList(title: context.viewState.terminology.objectiveSuccessMetrics, items: section.objective.successMetrics)
            }
            if !section.objective.exitOptions.isEmpty {
                readOnlyList(title: context.viewState.terminology.objectiveExitOptions, items: section.objective.exitOptions)
            }
            ForEach(section.tasks) { task in
                taskRow(task)
            }
        } header: {
            Text(section.objective.title)
                .compoundListSectionHeader()
        }
    }
    
    /// `success_metrics`/`exit_options` are read-only context (§3.4) — the authoritative
    /// completion signal is the objective's `status`, and real decisions still go through the
    /// existing choice_request cards, so these are never interactive.
    private func readOnlyList(title: String, items: [String]) -> some View {
        ListRow(label: .plain(title: title,
                              description: items.map { "· \($0)" }.joined(separator: "\n")),
                kind: .label)
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
            Text(context.viewState.terminology.taskPanelEmpty)
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
    static let objectivesViewModel = makeViewModel(summary: objectivesSummary)
    
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
        
        ElementNavigationStack {
            AgentTaskPanelScreen(context: objectivesViewModel.context)
        }
        .previewDisplayName("Objectives")
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
    
    static var objectivesSummary: RoomTaskSummary {
        RoomTaskSummary(activeTasks: [
            .init(eventID: "$task-1", taskID: "task-1", title: "验证真机趋势线", isResolved: false,
                  doneStepCount: 1, totalStepCount: 3, steps: [], threadRootEventID: nil, updatedAt: nil, objectiveID: "obj-1"),
            .init(eventID: "$task-2", taskID: "task-2", title: "补齐单元测试", isResolved: false,
                  doneStepCount: 0, totalStepCount: 2, steps: [], threadRootEventID: nil, updatedAt: nil, objectiveID: "obj-1"),
            .init(eventID: "$task-3", taskID: "task-3", title: "无挂靠的杂项差事", isResolved: false,
                  doneStepCount: 0, totalStepCount: 1, steps: [], threadRootEventID: nil, updatedAt: nil, objectiveID: nil)
        ],
        objectives: [
            .init(objectiveID: "obj-1", title: "验证指标趋势图在真实数据下可用", status: .active,
                  successMetrics: ["真机上看到真实历史点渲染出趋势线", "连续切换视图模式不崩溃"],
                  exitOptions: ["直接发布", "先收集一周真实数据再定稿", "放弃这个方向"],
                  priority: 1, updatedAt: .now)
        ])
    }
    
    static func makeViewModel(summary: RoomTaskSummary) -> AgentTaskPanelScreenViewModel {
        AgentTaskPanelScreenViewModel(summaryPublisher: CurrentValueSubject<RoomTaskSummary, Never>(summary).asCurrentValuePublisher(), appSettings: .volatile())
    }
}
