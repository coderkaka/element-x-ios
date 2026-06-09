//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

@MainActor protocol SecureBackupRecoveryKeyCoordinatorProtocol: CoordinatorProtocol {
    var actions: AnyPublisher<SecureBackupRecoveryKeyScreenCoordinatorAction, Never> { get }
}

protocol RecoveryKeyScreenHookProtocol {
    @MainActor func update(_ coordinator: any SecureBackupRecoveryKeyCoordinatorProtocol, homeserver: String, viewMode: SecureBackupRecoveryKeyScreenViewMode) -> any SecureBackupRecoveryKeyCoordinatorProtocol
}

struct DefaultRecoveryKeyScreenHook: RecoveryKeyScreenHookProtocol {
    @MainActor func update(_ coordinator: any SecureBackupRecoveryKeyCoordinatorProtocol, homeserver: String, viewMode: SecureBackupRecoveryKeyScreenViewMode) -> any SecureBackupRecoveryKeyCoordinatorProtocol {
        coordinator
    }
}
