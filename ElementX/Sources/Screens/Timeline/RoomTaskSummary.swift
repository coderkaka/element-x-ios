//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Everything the room's timeline currently knows about its agent tasks: every
/// `io.element.agent.canvas.steps` task grouped by resolution, plus any
/// `io.element.agent.choice_request`s still awaiting an answer.
nonisolated struct RoomTaskSummary: Equatable {
    struct Task: Identifiable, Equatable {
        let eventID: String // presenting message event (for detail push)
        let taskID: String
        let title: String
        let isResolved: Bool
        let doneStepCount: Int
        let totalStepCount: Int
        let steps: [CanvasStep] // current steps (state-event-resolved)
        let threadRootEventID: String?
        let updatedAt: Date?
        var id: String {
            eventID
        }
    }
    
    struct PendingChoice: Identifiable, Equatable {
        let eventID: String // the choice_request message (for scroll-to)
        let question: String
        var id: String {
            eventID
        }
    }
    
    var activeTasks: [Task] = [] // 在办, updatedAt desc where known
    var doneTasks: [Task] = [] // 已结
    var pendingChoices: [PendingChoice] = [] // 待批
    var isEmpty: Bool {
        activeTasks.isEmpty && doneTasks.isEmpty && pendingChoices.isEmpty
    }
}
