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

    @Namespace private var navigationTransitionNamespace
    private enum NavigationTransitionSourceID {
        case spaceFilters
    }

    var body: some View {
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
        .navigationTitle(context.viewState.navigationTitle)
        // The `.principal` toolbar title button (`navigationTitleButton`) already renders the
        // title — without `.inline` the large title also renders, showing it twice. The
        // `.navigationTitle` itself stays for the back-button label/a11y.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                settingsButton
            }
            ToolbarItem(placement: .principal) {
                navigationTitleButton
            }
            ToolbarItem(placement: .primaryAction) {
                viewModeMenu
            }
            // Mirrors HomeScreen's own trailing-item spacing so the two buttons don't crowd
            // together.
            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) {
                spaceFiltersButton
            }
        }
        .sheet(item: $context.spaceFiltersViewModel) { viewModel in
            ChatsSpaceFiltersScreen(context: viewModel.context)
                .navigationTransition(.zoom(sourceID: NavigationTransitionSourceID.spaceFilters,
                                            in: navigationTransitionNamespace))
        }
    }

    /// The dynamic navigation title (fix-spacebar3 contract A0) — mirrors 政事堂's
    /// `HomeScreen.navigationTitleButton` verbatim: same chevron affordance, same tap target
    /// (`.spaceFilters`, the same panel the trailing icon button opens). 差事's toolbar has no
    /// `shouldShowSpaceFilters` gate (unlike 政事堂), so this is shown unconditionally, matching
    /// `spaceFiltersButton` below which is also always visible.
    private var navigationTitleButton: some View {
        Button {
            context.send(viewAction: .spaceFilters)
        } label: {
            HStack(spacing: 4) {
                Text(context.viewState.navigationTitle)
                    .font(.compound.headingMDBold)
                    .foregroundColor(.compound.textPrimary)
                    .lineLimit(1)
                CompoundIcon(\.chevronDown, size: .xSmall, relativeTo: .compound.headingMDBold)
                    .foregroundColor(.compound.iconSecondary)
            }
        }
        .accessibilityLabel(L10n.screenRoomlistYourSpaces)
    }

    /// The same 道 picker button/panel 政事堂 uses (fix-spacebar3 contract B) — selection is
    /// driven by `appSettings.selectedSpaceFilterRoomID`, the single source of truth both tabs
    /// observe, so picking a 道 here keeps 政事堂 in sync and vice versa.
    private var spaceFiltersButton: some View {
        Button {
            context.send(viewAction: .spaceFilters)
        } label: {
            CompoundIcon(\.filter)
                .overlayBadge(10, isBadged: context.viewState.hasPendingSpaceInvites)
        }
        .accessibilityLabel(L10n.screenRoomlistYourSpaces)
        .matchedTransitionSource(id: NavigationTransitionSourceID.spaceFilters,
                                 in: navigationTransitionNamespace)
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
        appSettings.selectedSpaceFilterRoomID = selectedSpaceFilterRoomID
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@alice:example.com"))))
        return AgentTasksScreenViewModel(userSession: userSession,
                                         agentIndexService: indexService,
                                         spaceService: spaceService,
                                         appSettings: appSettings)
    }
}
