//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine

// sourcery: AutoMockable
protocol AgentIndexServiceProtocol {
    var tasksPublisher: CurrentValuePublisher<[AgentTaskSummary], Never> { get }
    var projectsPublisher: CurrentValuePublisher<[AgentProjectSummary], Never> { get }
    var pendingChoicesPublisher: CurrentValuePublisher<[AgentPendingChoiceSummary], Never> { get }
    func start()
    
    /// Fetches a task's `metric` value-over-time history, oldest first, by paginating its
    /// room's timeline — bounded to `limit` revisions. Not part of the reactive task index:
    /// this is a one-shot, on-demand fetch (only called when the user opens the metric
    /// dashboard), since scanning timeline history is heavier than the index's own local-store
    /// read and isn't needed for every task on every launch.
    func metricHistory(roomID: String, taskID: String, limit: UInt32) async -> [AgentTaskMetricHistoryPoint]
}
