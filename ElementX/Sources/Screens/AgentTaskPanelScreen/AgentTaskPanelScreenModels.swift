//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// One 标的(objective) heading in the panel, with the active 差事 filed under it.
struct AgentTaskPanelObjectiveSection: Identifiable, Equatable {
    let objective: RoomTaskSummary.Objective
    let tasks: [RoomTaskSummary.Task]
    var id: String {
        objective.id
    }
}

struct AgentTaskPanelScreenViewState: BindableState {
    var pendingChoices: [RoomTaskSummary.PendingChoice] = []
    var activeTasks: [RoomTaskSummary.Task] = []
    var doneTasks: [RoomTaskSummary.Task] = []
    var objectives: [RoomTaskSummary.Objective] = []
    var terminology = AppTerminology(scenario: .imperial)
    
    var isEmpty: Bool {
        pendingChoices.isEmpty && activeTasks.isEmpty && doneTasks.isEmpty
    }
    
    /// Active objectives (updatedAt desc), each with the active 差事 that point at it via
    /// `objectiveID`. Empty objectives are still shown — the standing goal matters even before a
    /// task is filed under it. Done/abandoned objectives don't get a section.
    var objectiveSections: [AgentTaskPanelObjectiveSection] {
        let tasksByObjectiveID = Dictionary(grouping: activeTasks.compactMap { task in task.objectiveID.map { ($0, task) } },
                                            by: \.0)
            .mapValues { $0.map(\.1) }
        return objectives
            .filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { AgentTaskPanelObjectiveSection(objective: $0, tasks: tasksByObjectiveID[$0.objectiveID] ?? []) }
    }
    
    /// Active 差事 not filed under any *active* objective (no `objectiveID`, or one pointing at a
    /// done/abandoned/unknown objective) — shown in a plain trailing section.
    var ungroupedActiveTasks: [RoomTaskSummary.Task] {
        let activeObjectiveIDs = Set(objectives.filter { $0.status == .active }.map(\.objectiveID))
        return activeTasks.filter { task in
            guard let objectiveID = task.objectiveID else { return true }
            return !activeObjectiveIDs.contains(objectiveID)
        }
    }
}

enum AgentTaskPanelScreenViewAction: CustomStringConvertible {
    case taskTapped(RoomTaskSummary.Task)
    case choiceTapped(eventID: String)
    
    var description: String {
        switch self {
        case .taskTapped: "taskTapped"
        case .choiceTapped: "choiceTapped"
        }
    }
}

enum AgentTaskPanelScreenViewModelAction: Equatable {
    case presentTaskDetail(task: RoomTaskSummary.Task)
    case focusTimelineEvent(eventID: String)
}
