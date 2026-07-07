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
    var unresolvedTasks: [AgentTaskSummary] = []
    var resolvedTasks: [AgentTaskSummary] = []
    var kanbanColumns: [AgentTasksKanbanColumn] = []
    var isKanbanViewEnabled = false
    var terminology = AppTerminology(scenario: .imperial)
    
    var isEmpty: Bool {
        unresolvedTasks.isEmpty && resolvedTasks.isEmpty
    }
}

enum AgentTasksScreenViewAction: CustomStringConvertible {
    case taskTapped(AgentTaskSummary)
    case toggleViewMode
    
    var description: String {
        switch self {
        case .taskTapped: "taskTapped"
        case .toggleViewMode: "toggleViewMode"
        }
    }
}

enum AgentTasksScreenViewModelAction: Equatable {
    case presentCanvasSteps(roomID: String, taskID: String)
}
