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
    /// selection — `nil` means unfiltered (全部). No longer rendered as its own text (the shared
    /// `SpaceTabBarView`'s selected chip is now the visible indicator, fix-kanban2 contract B) —
    /// kept because `scopeToSelectedSpace` produces it as part of the scoping computation anyway.
    var selectedSpaceFilterName: String?
    /// The raw room ID backing `selectedSpaceFilterName` — `nil` means 全部. Kept alongside the
    /// name so the 道条 can mark the current selection even if two 道 happen to share a name.
    var selectedSpaceFilterRoomID: String?
    /// The full 道 list the 道条 is built from — same source as 政事堂's own.
    var availableSpaceFilters: [SpaceServiceFilter] = []
    /// User-customised 道 chip order, live-mirrored from `AppSettings.spaceFilterOrder` — shared
    /// with 政事堂 since both tabs render the same `SpaceTabBarView` over the same order setting.
    var spaceFilterOrder: [String] = []
    /// Whether the user has an unseen invite to a 道 (Space) not in `availableSpaceFilters` —
    /// same algorithm as `HomeScreenViewModel`'s own copy (see `hasPendingSpaceInvite(in:seenInvites:)`),
    /// badges the "全部" chip since the space graph only surfaces joined spaces.
    var hasPendingSpaceInvites = false

    var topLevelSpaceFilters: [SpaceServiceFilter] {
        sortSpaceFilters(availableSpaceFilters.filter { $0.level == 0 }, byOrder: spaceFilterOrder)
    }

    var selectedSpaceFilter: SpaceServiceFilter? {
        topLevelSpaceFilters.first { $0.room.id == selectedSpaceFilterRoomID }
    }

    var isEmpty: Bool {
        unresolvedTasks.isEmpty && resolvedTasks.isEmpty
    }
}

enum AgentTasksScreenViewAction: CustomStringConvertible {
    case taskTapped(AgentTaskSummary)
    case setViewMode(AgentTasksViewMode)
    case loadMetricHistory(AgentTaskSummary)
    case showSettings
    /// `nil` selects 全部 (unfiltered).
    case selectSpaceFilter(String?)
    case reorderSpaceFilter(roomID: String, direction: MoveDirection)
    case manageSpaces

    var description: String {
        switch self {
        case .taskTapped: "taskTapped"
        case .setViewMode(let mode): "setViewMode(\(mode.rawValue))"
        case .loadMetricHistory: "loadMetricHistory"
        case .showSettings: "showSettings"
        case .selectSpaceFilter(let roomID): "selectSpaceFilter(\(roomID ?? "nil"))"
        case .reorderSpaceFilter(let roomID, let direction): "reorderSpaceFilter(\(roomID), \(direction))"
        case .manageSpaces: "manageSpaces"
        }
    }
}

enum AgentTasksScreenViewModelAction: Equatable {
    case presentCanvasSteps(roomID: String, taskID: String)
    case showSettings
    case showSpaceManagement
}
