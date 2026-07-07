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
        /// The presenting message's event ID, for detail push and scroll-to. Empty for tasks known
        /// only from room state (no matching message has been paginated into the timeline yet).
        var eventID: String
        let taskID: String
        let title: String
        let isResolved: Bool
        let doneStepCount: Int
        let totalStepCount: Int
        let steps: [CanvasStep] // current steps (state-event-resolved)
        let threadRootEventID: String?
        let updatedAt: Date?
        /// The 标的(`Objective.objectiveID`) this task belongs to, if any — drives the 案卷面板's
        /// per-objective grouping. `nil` tasks fall into the ungrouped section.
        var objectiveID: String?
        /// `taskID`, not `eventID` — state-only tasks (not yet paginated into the timeline) have no
        /// event ID, and a task's identity shouldn't change once its presenting message loads.
        var id: String {
            taskID
        }
        
        /// Explicit init so `objectiveID` can default without a stored-property `= nil` (which
        /// SwiftFormat's redundantNilInit would strip, breaking the default).
        init(eventID: String, taskID: String, title: String, isResolved: Bool, doneStepCount: Int, totalStepCount: Int,
             steps: [CanvasStep], threadRootEventID: String?, updatedAt: Date?, objectiveID: String? = nil) {
            self.eventID = eventID
            self.taskID = taskID
            self.title = title
            self.isResolved = isResolved
            self.doneStepCount = doneStepCount
            self.totalStepCount = totalStepCount
            self.steps = steps
            self.threadRootEventID = threadRootEventID
            self.updatedAt = updatedAt
            self.objectiveID = objectiveID
        }
    }
    
    struct PendingChoice: Identifiable, Equatable {
        let eventID: String // the choice_request message (for scroll-to)
        let question: String
        var id: String {
            eventID
        }
    }
    
    /// A 标的(阶段目标) declared in this room — `io.element.agent.objective`, see §3.4. The panel
    /// groups tasks under it and shows `successMetrics`/`exitOptions` as read-only context.
    struct Objective: Identifiable, Equatable {
        let objectiveID: String
        let title: String
        let status: AgentObjectiveStatus
        let successMetrics: [String]
        let exitOptions: [String]
        let priority: Int
        let updatedAt: Date
        var id: String {
            objectiveID
        }
    }
    
    var activeTasks: [Task] = [] // 在办, updatedAt desc where known
    var doneTasks: [Task] = [] // 已结
    var pendingChoices: [PendingChoice] = [] // 待批
    var objectives: [Objective] = [] // 标的, active ones drive the panel's grouping sections
    var isEmpty: Bool {
        activeTasks.isEmpty && doneTasks.isEmpty && pendingChoices.isEmpty
    }
}
