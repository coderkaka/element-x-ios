//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Charts
import Compound
import SwiftUI

struct AgentTasksScreen: View {
    @Bindable var context: AgentTasksScreenViewModel.Context
    
    var body: some View {
        VStack(spacing: 0) {
            spaceFilterMenu

            Group {
                // Kanban's status columns are always shown (even empty) as a fixed skeleton —
                // don't let an empty task list hide the switcher's own destination. List/metric
                // still show the friendlier "empty" message instead of a bare blank screen.
                if context.viewState.isEmpty, context.viewState.viewMode != .kanban {
                    emptyState
                } else {
                    switch context.viewState.viewMode {
                    case .list: taskList
                    case .kanban: kanbanBoard
                    case .metric: metricDashboard
                    }
                }
            }
        }
        .navigationTitle(context.viewState.terminology.tabTasks)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                settingsButton
            }
            ToolbarItem(placement: .primaryAction) {
                viewModeMenu
            }
        }
    }

    /// The 道 filter as a tappable menu (listing 全部 + every top-level 道, same source as
    /// 政事堂's own 道条) — always shown, including when unfiltered, so it doubles as the entry
    /// point into switching 道 without going back to 政事堂.
    private var spaceFilterMenu: some View {
        Menu {
            Button {
                context.send(viewAction: .selectSpaceFilter(nil))
            } label: {
                if context.viewState.selectedSpaceFilterRoomID == nil {
                    Label(UntranslatedL10n.screenHomeSpaceAll, icon: \.check)
                } else {
                    Text(UntranslatedL10n.screenHomeSpaceAll)
                }
            }
            ForEach(context.viewState.topLevelSpaceFilters) { filter in
                Button {
                    context.send(viewAction: .selectSpaceFilter(filter.room.id))
                } label: {
                    if context.viewState.selectedSpaceFilterRoomID == filter.room.id {
                        Label(filter.room.name, icon: \.check)
                    } else {
                        Text(filter.room.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                CompoundIcon(\.space, size: .xSmall, relativeTo: .compound.bodySM)
                    .foregroundColor(.compound.iconTertiary)
                    .accessibilityHidden(true)
                Text(spaceFilterMenuLabel)
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textSecondary)
                    .lineLimit(1)
                CompoundIcon(\.chevronDown, size: .xSmall, relativeTo: .compound.bodySM)
                    .foregroundColor(.compound.iconTertiary)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.compound.bgSubtleSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spaceFilterMenuLabel)
    }

    private var spaceFilterMenuLabel: String {
        if let name = context.viewState.selectedSpaceFilterName {
            context.viewState.terminology.spaceFilterIndicator(name: name)
        } else {
            UntranslatedL10n.screenHomeSpaceAll
        }
    }

    private var settingsButton: some View {
        Button {
            context.send(viewAction: .showSettings)
        } label: {
            LoadableAvatarImage(url: context.viewState.userAvatarURL,
                                name: context.viewState.userDisplayName,
                                contentID: context.viewState.userID,
                                avatarSize: .user(on: .chats),
                                mediaProvider: context.mediaProvider)
                .clipShape(.circle)
                .compositingGroup()
        }
        .accessibilityLabel(L10n.commonSettings)
    }
    
    private var viewModeMenu: some View {
        Menu {
            Button {
                context.send(viewAction: .setViewMode(.list))
            } label: {
                Label(context.viewState.terminology.listViewA11yLabel, icon: \.listView)
            }
            Button {
                context.send(viewAction: .setViewMode(.kanban))
            } label: {
                Label(context.viewState.terminology.kanbanViewA11yLabel, icon: \.grid)
            }
            Button {
                context.send(viewAction: .setViewMode(.metric))
            } label: {
                Label(context.viewState.terminology.metricViewA11yLabel, icon: \.chart)
            }
        } label: {
            CompoundIcon(viewModeIcon)
        }
        .accessibilityLabel(currentViewModeA11yLabel)
    }
    
    private var viewModeIcon: KeyPath<CompoundIcons, Image> {
        switch context.viewState.viewMode {
        case .list: \.listView
        case .kanban: \.grid
        case .metric: \.chart
        }
    }
    
    private var currentViewModeA11yLabel: String {
        switch context.viewState.viewMode {
        case .list: context.viewState.terminology.listViewA11yLabel
        case .kanban: context.viewState.terminology.kanbanViewA11yLabel
        case .metric: context.viewState.terminology.metricViewA11yLabel
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
                    Text(context.viewState.terminology.sectionActive)
                        .compoundListSectionHeader()
                }
            }
            
            if !context.viewState.resolvedTasks.isEmpty {
                Section {
                    ForEach(context.viewState.resolvedTasks) { task in
                        taskRow(task)
                    }
                } header: {
                    Text(context.viewState.terminology.sectionDone)
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
    
    private var kanbanBoard: some View {
        VStack(spacing: 0) {
            kanbanGroupingModeMenu

            // Scroll both axes: horizontal across columns, vertical so a column taller than the
            // screen is still reachable (a horizontal-only ScrollView left overflow stuck off-screen).
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(context.viewState.kanbanColumns) { column in
                        kanbanColumn(column)
                    }
                }
                .padding(16)
            }
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        }
    }

    /// Switches whether the board's columns are 按状态(default) or 按案 — a lightweight menu at
    /// the kanban content's own top, matching `viewModeMenu`'s style.
    private var kanbanGroupingModeMenu: some View {
        Menu {
            Button {
                context.send(viewAction: .setKanbanGroupingMode(.status))
            } label: {
                if context.viewState.kanbanGroupingMode == .status {
                    Label(context.viewState.terminology.kanbanGroupByStatusLabel, icon: \.check)
                } else {
                    Text(context.viewState.terminology.kanbanGroupByStatusLabel)
                }
            }
            Button {
                context.send(viewAction: .setKanbanGroupingMode(.room))
            } label: {
                if context.viewState.kanbanGroupingMode == .room {
                    Label(context.viewState.terminology.kanbanGroupByRoomLabel, icon: \.check)
                } else {
                    Text(context.viewState.terminology.kanbanGroupByRoomLabel)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentKanbanGroupingModeLabel)
                CompoundIcon(\.chevronDown, size: .xSmall, relativeTo: .compound.bodySM)
            }
            .font(.compound.bodySM)
            .foregroundColor(.compound.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(currentKanbanGroupingModeLabel)
    }

    private var currentKanbanGroupingModeLabel: String {
        switch context.viewState.kanbanGroupingMode {
        case .status: context.viewState.terminology.kanbanGroupByStatusLabel
        case .room: context.viewState.terminology.kanbanGroupByRoomLabel
        }
    }

    private func kanbanColumn(_ column: AgentTasksKanbanColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(column.title)
                .font(.compound.bodyMDSemibold)
                .foregroundColor(.compound.textPrimary)
                .lineLimit(1)
            
            VStack(spacing: 8) {
                ForEach(column.tasks) { task in
                    kanbanCard(task)
                }
            }
        }
        .frame(width: 240, alignment: .top)
    }
    
    private func kanbanCard(_ task: AgentTaskSummary) -> some View {
        Button {
            context.send(viewAction: .taskTapped(task))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title ?? task.taskID)
                    .font(.compound.bodyMDSemibold)
                    .foregroundColor(.compound.textPrimary)
                    .lineLimit(2)
                Text(task.roomName)
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textSecondary)
                    .lineLimit(1)
                
                if task.totalStepCount > 0 {
                    if context.viewState.terminology.prefersProgressBar {
                        kanbanCardProgressBar(task)
                    } else {
                        Text(context.viewState.terminology.roomTaskProgress(done: String(task.doneStepCount), total: String(task.totalStepCount)))
                            .font(.compound.bodyXS)
                            .foregroundColor(.compound.textSecondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.compound.bgSubtleSecondary))
        }
        .buttonStyle(.plain)
    }
    
    /// Mirrors `HomeScreenRoomCell.taskProgressBar` — same done/total shape, one task's own
    /// steps here rather than a room's aggregate task count.
    private func kanbanCardProgressBar(_ task: AgentTaskSummary) -> some View {
        let progress = Double(task.doneStepCount) / Double(task.totalStepCount)
        return HStack(spacing: 4) {
            ProgressView(value: progress)
                .frame(width: 40)
                .tint(.compound.iconAccentTertiary)
            Text("\(Int((progress * 100).rounded()))%")
                .font(.compound.bodyXS)
                .foregroundColor(.compound.textSecondary)
        }
    }
    
    private var metricDashboard: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(context.viewState.metricTasks) { task in
                    metricCard(task)
                }
            }
            .padding(16)
        }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
    }
    
    private func metricCard(_ task: AgentTaskSummary) -> some View {
        Button {
            context.send(viewAction: .taskTapped(task))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title ?? task.taskID)
                    .font(.compound.bodyMDSemibold)
                    .foregroundColor(.compound.textPrimary)
                    .lineLimit(2)
                Text(task.roomName)
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textSecondary)
                    .lineLimit(1)
                
                if let metric = task.metric {
                    Text("\(metric.formattedCurrent)/\(metric.formattedTarget) \(metric.unit)")
                        .font(.compound.bodyXS)
                        .foregroundColor(.compound.textSecondary)
                }
                
                metricChart(history: context.viewState.metricHistories[task.id])
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.compound.bgSubtleSecondary))
        }
        .buttonStyle(.plain)
        .task {
            context.send(viewAction: .loadMetricHistory(task))
        }
    }
    
    @ViewBuilder
    private func metricChart(history: [AgentTaskMetricHistoryPoint]?) -> some View {
        switch history {
        case .none:
            ProgressView()
                .frame(height: 60)
                .frame(maxWidth: .infinity)
        case .some(let points) where points.count > 1:
            // id by offset, not `\.date`: two revisions can share an origin_server_ts (batch
            // writes / same-ms edits), and `id: \.date` would collapse them and drop a point.
            Chart(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("date", point.date), y: .value("value", point.metric.current))
            }
            .frame(height: 60)
        case .some:
            EmptyView()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            CompoundIcon(\.polls, size: .medium, relativeTo: .compound.bodyLG)
                .foregroundColor(.compound.iconSecondary)
                .accessibilityHidden(true)
            Text(context.viewState.terminology.agentTasksEmpty)
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
    static let kanbanViewModel = makeViewModel(tasks: [
        .init(roomID: "!a:example.com", roomName: "Backend", taskID: "task-1",
              title: "Refactor auth module", isResolved: false, doneStepCount: 1, totalStepCount: 3),
        .init(roomID: "!d:example.com", roomName: "iOS App", taskID: "task-4",
              title: "Ship the kanban view", isResolved: false, doneStepCount: 2, totalStepCount: 2),
        .init(roomID: "!e:example.com", roomName: "Standalone", taskID: "task-5",
              title: "A finished task", isResolved: true, doneStepCount: 1, totalStepCount: 1)
    ], spaceFilters: [
        .init(room: .mock(id: "!a:example.com", name: "工程院", isSpace: true), level: 0, descendants: ["!a:example.com"]),
        .init(room: .mock(id: "!d:example.com", name: "上林苑", isSpace: true), level: 0, descendants: ["!d:example.com"])
    ], viewMode: .kanban)
    static let kanbanByRoomViewModel = makeViewModel(tasks: [
        .init(roomID: "!a:example.com", roomName: "Backend", taskID: "task-1",
              title: "Refactor auth module", isResolved: false, doneStepCount: 1, totalStepCount: 3,
              updatedAt: Date(timeIntervalSince1970: 1_751_000_000)),
        .init(roomID: "!d:example.com", roomName: "iOS App", taskID: "task-4",
              title: "Ship the kanban view", isResolved: false, doneStepCount: 2, totalStepCount: 2,
              updatedAt: Date(timeIntervalSince1970: 1_751_100_000)),
        .init(roomID: "!e:example.com", roomName: "", taskID: "task-5",
              title: "A task in a room with no display name", isResolved: false, doneStepCount: 0, totalStepCount: 1)
    ], viewMode: .kanban, kanbanGroupingMode: .room)
    static let emptyKanbanViewModel = makeViewModel(tasks: [], viewMode: .kanban)
    static let metricTaskWithHistory = AgentTaskSummary(roomID: "!a:example.com", roomName: "Hermes案", taskID: "task-1", title: "内存占用瘦身",
                                                        isResolved: false, doneStepCount: 2, totalStepCount: 3,
                                                        metric: .init(current: 310, target: 300, unit: "MB"))
    static let spaceFilteredViewModel = makeViewModel(tasks: [
        .init(roomID: "!a:example.com", roomName: "Backend", taskID: "task-1",
              title: "Refactor auth module", isResolved: false, doneStepCount: 1, totalStepCount: 3),
        .init(roomID: "!d:example.com", roomName: "iOS App", taskID: "task-4",
              title: "A task in a different 道", isResolved: false, doneStepCount: 2, totalStepCount: 2)
    ], spaceFilters: [
        .init(room: .mock(id: "!a:example.com", name: "工程院", isSpace: true), level: 0, descendants: ["!a:example.com"]),
        .init(room: .mock(id: "!d:example.com", name: "上林苑", isSpace: true), level: 0, descendants: ["!d:example.com"])
    ], selectedSpaceFilterRoomID: "!a:example.com")
    static let metricViewModel = makeViewModel(tasks: [
        metricTaskWithHistory,
        .init(roomID: "!f:example.com", roomName: "无历史记录的差事", taskID: "task-6", title: "刚起步的指标任务",
              isResolved: false, doneStepCount: 0, totalStepCount: 1,
              metric: .init(current: 1, target: 10, unit: "件"))
    ], viewMode: .metric, metricHistory: [
        metricTaskWithHistory.id: [
            .init(metric: .init(current: 420, target: 300, unit: "MB"), date: Date(timeIntervalSince1970: 1_751_000_000)),
            .init(metric: .init(current: 360, target: 300, unit: "MB"), date: Date(timeIntervalSince1970: 1_751_050_000)),
            .init(metric: .init(current: 310, target: 300, unit: "MB"), date: Date(timeIntervalSince1970: 1_751_100_000))
        ]
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
        
        ElementNavigationStack {
            AgentTasksScreen(context: kanbanViewModel.context)
        }
        .previewDisplayName("Kanban")

        ElementNavigationStack {
            AgentTasksScreen(context: kanbanByRoomViewModel.context)
        }
        .previewDisplayName("Kanban by room")

        ElementNavigationStack {
            AgentTasksScreen(context: emptyKanbanViewModel.context)
        }
        .previewDisplayName("Empty kanban")

        ElementNavigationStack {
            AgentTasksScreen(context: metricViewModel.context)
        }
        .previewDisplayName("Metric")

        ElementNavigationStack {
            AgentTasksScreen(context: spaceFilteredViewModel.context)
        }
        .previewDisplayName("Space filtered")
    }

    static func makeViewModel(tasks: [AgentTaskSummary],
                              spaceFilters: [SpaceServiceFilter] = [],
                              viewMode: AgentTasksViewMode = .list,
                              kanbanGroupingMode: AgentTasksKanbanGroupingMode = .status,
                              metricHistory: [String: [AgentTaskMetricHistoryPoint]] = [:],
                              selectedSpaceFilterRoomID: String? = nil) -> AgentTasksScreenViewModel {
        let indexService = AgentIndexServiceMock()
        indexService.underlyingTasksPublisher = .init(tasks)
        indexService.metricHistoryRoomIDTaskIDLimitClosure = { roomID, taskID, _ in
            metricHistory["\(roomID)|\(taskID)"] ?? []
        }
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init(spaceFilters)
        let appSettings: AppSettings = .volatile()
        appSettings.agentTasksViewMode = viewMode
        appSettings.agentTasksKanbanGroupingMode = kanbanGroupingMode
        appSettings.selectedSpaceFilterRoomID = selectedSpaceFilterRoomID
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@alice:example.com"))))
        return AgentTasksScreenViewModel(userSession: userSession,
                                         agentIndexService: indexService,
                                         spaceService: spaceService,
                                         appSettings: appSettings)
    }
}
