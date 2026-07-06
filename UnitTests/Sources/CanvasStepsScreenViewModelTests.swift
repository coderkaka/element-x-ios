//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Testing

@MainActor
struct CanvasStepsScreenViewModelTests {
    @Test
    func closeDismisses() async throws {
        let viewModel = makeViewModel()
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            guard case .dismiss = action else { return false }
            return true
        }
        viewModel.context.send(viewAction: .close)
        try await deferred.fulfill()
    }
    
    @Test
    func viewThreadPresentsTheTaskThread() async throws {
        let viewModel = makeViewModel(threadRootEventID: "$thread-root")
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            guard case .presentThread(let threadRootEventID) = action else { return false }
            return threadRootEventID == "$thread-root"
        }
        viewModel.context.send(viewAction: .viewThread)
        try await deferred.fulfill()
    }
    
    @Test
    func viewThreadWithoutThreadRootDoesNothing() async throws {
        let viewModel = makeViewModel()
        
        let deferred = deferFailure(viewModel.actionsPublisher, timeout: .seconds(1)) { _ in true }
        viewModel.context.send(viewAction: .viewThread)
        try await deferred.fulfill()
    }
    
    // MARK: - Helpers
    
    private func makeViewModel(threadRootEventID: String? = nil) -> CanvasStepsScreenViewModel {
        CanvasStepsScreenViewModel(title: "Refactor auth module",
                                   steps: [CanvasStep(id: "s1", label: "Read existing code", status: .done)],
                                   taskID: "task-1",
                                   threadRootEventID: threadRootEventID,
                                   roomProxy: JoinedRoomProxyMock(.init(id: "1")),
                                   appSettings: .volatile())
    }
}
