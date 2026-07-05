//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

struct AgentTaskPanelScreenViewState: BindableState {
    var pendingChoices: [RoomTaskSummary.PendingChoice] = []
    var activeTasks: [RoomTaskSummary.Task] = []
    var doneTasks: [RoomTaskSummary.Task] = []
    
    var isEmpty: Bool {
        pendingChoices.isEmpty && activeTasks.isEmpty && doneTasks.isEmpty
    }
}

enum AgentTaskPanelScreenViewAction {
    case taskTapped(RoomTaskSummary.Task)
    case choiceTapped(eventID: String)
}

enum AgentTaskPanelScreenViewModelAction: Equatable {
    case presentTaskDetail(task: RoomTaskSummary.Task)
    case focusTimelineEvent(eventID: String)
}
