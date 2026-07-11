//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

extension AgentIndexServiceMock {
    struct Configuration {
        var tasks: [AgentTaskSummary] = []
        var projects: [AgentProjectSummary] = []
        var pendingChoices: [AgentPendingChoiceSummary] = []
        var objectives: [AgentObjectiveSummary] = []
    }
    
    convenience init(_ configuration: Configuration) {
        self.init()
        
        underlyingTasksPublisher = CurrentValuePublisher(configuration.tasks)
        underlyingProjectsPublisher = CurrentValuePublisher(configuration.projects)
        underlyingPendingChoicesPublisher = CurrentValuePublisher(configuration.pendingChoices)
        underlyingObjectivesPublisher = CurrentValuePublisher(configuration.objectives)
    }
}
