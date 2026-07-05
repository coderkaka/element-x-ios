//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias MessagesScreenViewModelType = StateStoreViewModelV2<MessagesScreenViewState, MessagesScreenViewAction>

class MessagesScreenViewModel: MessagesScreenViewModelType, MessagesScreenViewModelProtocol {
    private let roomSummaryProvider: RoomSummaryProviderProtocol
    private let appSettings: AppSettings
    
    private let actionsSubject: PassthroughSubject<MessagesScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<MessagesScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(roomSummaryProvider: RoomSummaryProviderProtocol, appSettings: AppSettings, mediaProvider: MediaProviderProtocol) {
        self.roomSummaryProvider = roomSummaryProvider
        self.appSettings = appSettings
        
        super.init(initialViewState: MessagesScreenViewState(), mediaProvider: mediaProvider)
        
        roomSummaryProvider.roomListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summaries in
                self?.updateRooms(with: summaries)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public
    
    override func process(viewAction: MessagesScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .selectRoom(let roomIdentifier):
            actionsSubject.send(.presentRoom(roomID: roomIdentifier))
        }
    }
    
    // MARK: - Private
    
    private func updateRooms(with summaries: [RoomSummary]) {
        let seenInvites = appSettings.seenInvites
        
        state.rooms = summaries.map { summary in
            HomeScreenRoom(summary: summary,
                           roomListActivityVisibility: appSettings.roomListActivityVisibility,
                           seenInvites: seenInvites)
        }
    }
}
