//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

struct CanvasStepsScreenViewState: BindableState {
    /// A one-time snapshot of the task's title, taken when the screen is presented.
    let title: String
    /// A one-time snapshot of the task's steps, taken when the screen is presented.
    /// The screen does not live-update if the underlying event changes; reopen via the banner to refresh.
    let steps: [CanvasStep]
}

enum CanvasStepsScreenViewAction {
    case close
}

enum CanvasStepsScreenViewModelAction {
    case dismiss
}
