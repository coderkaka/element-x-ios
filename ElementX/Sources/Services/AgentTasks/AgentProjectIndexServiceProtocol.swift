//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine

// sourcery: AutoMockable
protocol AgentProjectIndexServiceProtocol {
    var projectsPublisher: CurrentValuePublisher<[AgentProjectSummary], Never> { get }
    var pendingChoicesPublisher: CurrentValuePublisher<[AgentPendingChoiceSummary], Never> { get }
    func start()
}
