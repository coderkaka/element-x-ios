//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// One column of the 差事 tab's kanban view — either a fixed task-status bucket (按状态 mode)
/// or all tasks belonging to one 案/room (按案 mode), depending on `AgentTasksKanbanGroupingMode`.
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
    var kanbanGroupingMode = AgentTasksKanbanGroupingMode.status
    var terminology = AppTerminology(scenario: .imperial)
    /// The name of the 道 (space) tasks are currently scoped to, mirroring 政事堂's own
    /// selection — `nil` means unfiltered (全部). Drives the indicator strip; the strip's actual
    /// wording goes through `terminology.spaceFilterIndicator(name:)`, not stored pre-rendered,
    /// so it stays correct if the 御案体/通俗版 toggle flips without a new space selection.
    var selectedSpaceFilterName: String?
    /// The raw room ID backing `selectedSpaceFilterName` — `nil` means 全部. Kept alongside the
    /// name so the 道 menu can mark the current selection even if two 道 happen to share a name.
    var selectedSpaceFilterRoomID: String?
    /// The full 道 list the 道 menu is built from — same source as 政事堂's own 道条.
    var availableSpaceFilters: [SpaceServiceFilter] = []
    /// User-customised 道 chip order, live-mirrored from `AppSettings.spaceFilterOrder` (the 差事
    /// tab doesn't itself support reordering, only reflects whatever 政事堂's chips currently show).
    var spaceFilterOrder: [String] = []
    
    var topLevelSpaceFilters: [SpaceServiceFilter] {
        sortSpaceFilters(availableSpaceFilters.filter { $0.level == 0 }, byOrder: spaceFilterOrder)
    }
    
    var isEmpty: Bool {
        unresolvedTasks.isEmpty && resolvedTasks.isEmpty
    }
}

enum AgentTasksScreenViewAction: CustomStringConvertible {
    case taskTapped(AgentTaskSummary)
    case setViewMode(AgentTasksViewMode)
    case setKanbanGroupingMode(AgentTasksKanbanGroupingMode)
    case loadMetricHistory(AgentTaskSummary)
    case showSettings
    /// `nil` selects 全部 (unfiltered).
    case selectSpaceFilter(String?)
    
    var description: String {
        switch self {
        case .taskTapped: "taskTapped"
        case .setViewMode(let mode): "setViewMode(\(mode.rawValue))"
        case .setKanbanGroupingMode(let mode): "setKanbanGroupingMode(\(mode.rawValue))"
        case .loadMetricHistory: "loadMetricHistory"
        case .showSettings: "showSettings"
        case .selectSpaceFilter(let roomID): "selectSpaceFilter(\(roomID ?? "nil"))"
        }
    }
}

enum AgentTasksScreenViewModelAction: Equatable {
    case presentCanvasSteps(roomID: String, taskID: String)
    case showSettings
}
