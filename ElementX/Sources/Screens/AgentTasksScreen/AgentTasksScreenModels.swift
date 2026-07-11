//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// One column of the 差事 tab's kanban view — a fixed task-status bucket (在办/已结).
struct AgentTasksKanbanColumn: Identifiable, Equatable {
    let id: String
    let title: String
    let tasks: [AgentTaskSummary]
}

struct AgentTasksScreenViewState: BindableState {
    let userID: String
    var userDisplayName: String?
    var userAvatarURL: URL?

    var unresolvedTasks: [AgentTaskSummary] = []
    var resolvedTasks: [AgentTaskSummary] = []
    var kanbanColumns: [AgentTasksKanbanColumn] = []
    /// Tasks that carry a `metric` field, for the 指标 view mode.
    var metricTasks: [AgentTaskSummary] = []
    /// Keyed by `AgentTaskSummary.id`, populated on-demand as the 指标 view mode's cards
    /// appear — fetching history for every metric task eagerly isn't worth it since most
    /// launches never open this view mode.
    var metricHistories: [String: [AgentTaskMetricHistoryPoint]] = [:]
    var loadingMetricTaskIDs: Set<String> = []
    var viewMode = AgentTasksViewMode.list
    var terminology = AppTerminology(scenario: .imperial)
    /// The name of the 道 (space) tasks are currently scoped to, mirroring 政事堂's own
    /// selection — `nil` means unfiltered (全部). Drives both the scoping and the dynamic
    /// navigation title (fix-spacebar3 contract A0).
    var selectedSpaceFilterName: String?
    /// Whether the user has an unseen invite to a 道 (Space) — same algorithm as
    /// `HomeScreenViewModel`'s own copy (see `hasPendingSpaceInvite(in:seenInvites:)`), badges
    /// the space picker button since the space graph only surfaces joined spaces.
    var hasPendingSpaceInvites = false

    var bindings: AgentTasksScreenViewStateBindings

    var isEmpty: Bool {
        unresolvedTasks.isEmpty && resolvedTasks.isEmpty
    }

    /// The navigation title: the selected 道's name when filtering, otherwise the plain 差事 tab
    /// title (fix-spacebar3 contract A0 — same rule as 政事堂's own title).
    var navigationTitle: String {
        selectedSpaceFilterName ?? terminology.tabTasks
    }
}

struct AgentTasksScreenViewStateBindings {
    /// Drives the 道 picker sheet (fix-spacebar3 contract B) — non-nil while it's presented.
    var spaceFiltersViewModel: ChatsSpaceFiltersScreenViewModel?
}

enum AgentTasksScreenViewAction: CustomStringConvertible {
    case taskTapped(AgentTaskSummary)
    case setViewMode(AgentTasksViewMode)
    case loadMetricHistory(AgentTaskSummary)
    case showSettings
    /// `nil` selects 全部 (unfiltered).
    case selectSpaceFilter(String?)
    /// Opens the 道 picker panel (`ChatsSpaceFiltersScreen`) — the same one 政事堂 uses.
    case spaceFilters
    case manageSpaces

    var description: String {
        switch self {
        case .taskTapped: "taskTapped"
        case .setViewMode(let mode): "setViewMode(\(mode.rawValue))"
        case .loadMetricHistory: "loadMetricHistory"
        case .showSettings: "showSettings"
        case .selectSpaceFilter(let roomID): "selectSpaceFilter(\(roomID ?? "nil"))"
        case .spaceFilters: "spaceFilters"
        case .manageSpaces: "manageSpaces"
        }
    }
}

enum AgentTasksScreenViewModelAction: Equatable {
    case presentCanvasSteps(roomID: String, taskID: String)
    case showSettings
    case showSpaceManagement
}
