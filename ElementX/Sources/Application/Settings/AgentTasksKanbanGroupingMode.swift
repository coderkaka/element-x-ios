//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

/// Which dimension the 差事 tab's 看板(kanban) view groups its columns by.
nonisolated enum AgentTasksKanbanGroupingMode: String, CaseIterable, Codable {
    /// Columns = task status (在办/已结) — fixed, always shown even when empty.
    case status
    /// Columns = 案 (room), one per room that has at least one task.
    case room
}
