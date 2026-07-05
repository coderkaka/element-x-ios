//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias CanvasStepsScreenViewModelType = StateStoreViewModelV2<CanvasStepsScreenViewState, CanvasStepsScreenViewAction>

class CanvasStepsScreenViewModel: CanvasStepsScreenViewModelType, CanvasStepsScreenViewModelProtocol {
    private let taskID: String
    private let roomProxy: JoinedRoomProxyProtocol

    private let actionsSubject: PassthroughSubject<CanvasStepsScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CanvasStepsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    /// The title/steps passed in are the presenting message's snapshot, shown immediately;
    /// current progress then comes from the task's room state event and is kept fresh while
    /// the screen is open (custom state event types aren't observable directly, so any room
    /// activity re-reads the state — same approach as `TimelineViewModel`).
    init(title: String, steps: [CanvasStep], taskID: String, roomProxy: JoinedRoomProxyProtocol) {
        self.taskID = taskID
        self.roomProxy = roomProxy

        super.init(initialViewState: CanvasStepsScreenViewState(title: title, steps: steps))

        refreshSteps()

        roomProxy.infoPublisher
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSteps()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public

    override func process(viewAction: CanvasStepsScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .close:
            actionsSubject.send(.dismiss)
        }
    }

    // MARK: - Private

    private func refreshSteps() {
        Task {
            guard case let .success(rawStateEvent) = await roomProxy.getStateEventRaw(eventType: AgentCanvasStepsRoomTimelineItemContent.msgType,
                                                                                      stateKey: taskID),
                  let stateContent = AgentCanvasStepsStateContent(parsingFrom: rawStateEvent) else {
                return // No state event yet (or unparseable) — keep showing the message snapshot.
            }

            state.steps = stateContent.steps
        }
    }
}
