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
    private let actionsSubject: PassthroughSubject<CanvasStepsScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CanvasStepsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    /// The title/steps are a one-time snapshot passed in by the caller (see `CanvasStepsScreenViewState`),
    /// there is no live re-subscription to the underlying timeline item in this V1 read-only screen.
    init(title: String, steps: [CanvasStep]) {
        super.init(initialViewState: CanvasStepsScreenViewState(title: title, steps: steps))
    }

    // MARK: - Public

    override func process(viewAction: CanvasStepsScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .close:
            actionsSubject.send(.dismiss)
        }
    }
}
