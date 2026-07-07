//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

/// The 差事 tab's 3 view modes.
nonisolated enum AgentTasksViewMode: String, CaseIterable, Codable {
    case list
    case kanban
    case metric
}
