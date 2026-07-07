//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// One column of the 差事 tab's kanban view — all tasks whose room sits under `spaceID`
/// (or the `nil`-ID fallback column for rooms not under any joined 道).
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
    
    var isEmpty: Bool {
        unresolvedTasks.isEmpty && resolvedTasks.isEmpty
    }
}

enum AgentTasksScreenViewAction: CustomStringConvertible {
    case taskTapped(AgentTaskSummary)
    case setViewMode(AgentTasksViewMode)
    case loadMetricHistory(AgentTaskSummary)
    case showSettings
    
    var description: String {
        switch self {
        case .taskTapped: "taskTapped"
        case .setViewMode(let mode): "setViewMode(\(mode.rawValue))"
        case .loadMetricHistory: "loadMetricHistory"
        case .showSettings: "showSettings"
        }
    }
}

enum AgentTasksScreenViewModelAction: Equatable {
    case presentCanvasSteps(roomID: String, taskID: String)
    case showSettings
}
