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
    /// Initially the steps from the presenting message; refreshed from the task's
    /// `io.element.agent.canvas.steps` room state event while the screen is open.
    var steps: [CanvasStep]
    /// The task's work thread, when it has one — shows the 查看实录 row.
    let threadRootEventID: String?
}

enum CanvasStepsScreenViewAction {
    case close
    case viewThread
}

enum CanvasStepsScreenViewModelAction {
    case dismiss
    case presentThread(threadRootEventID: String)
}
