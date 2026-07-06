//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

struct AgentTasksScreenViewState: BindableState {
    var unresolvedTasks: [AgentTaskSummary] = []
    var resolvedTasks: [AgentTaskSummary] = []
    var terminology = AppTerminology(scenario: .imperial)
    
    var isEmpty: Bool {
        unresolvedTasks.isEmpty && resolvedTasks.isEmpty
    }
}

enum AgentTasksScreenViewAction: CustomStringConvertible {
    case taskTapped(AgentTaskSummary)
    
    var description: String {
        switch self {
        case .taskTapped: "taskTapped"
        }
    }
}

enum AgentTasksScreenViewModelAction: Equatable {
    case presentRoom(roomID: String)
}
