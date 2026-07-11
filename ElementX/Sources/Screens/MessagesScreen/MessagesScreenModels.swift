//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

struct MessagesScreenViewState: BindableState {
    let userID: String
    var userDisplayName: String?
    var userAvatarURL: URL?
    
    var rooms: [HomeScreenRoom] = []
    var terminology = AppTerminology(scenario: .imperial)
}

enum MessagesScreenViewAction {
    case selectRoom(roomIdentifier: String)
    case showSettings
}

enum MessagesScreenViewModelAction: Equatable {
    case presentRoom(roomID: String)
    case showSettings
}
