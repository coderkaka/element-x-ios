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
    
    init(userSession: UserSessionProtocol, roomSummaryProvider: RoomSummaryProviderProtocol, appSettings: AppSettings) {
        self.roomSummaryProvider = roomSummaryProvider
        self.appSettings = appSettings
        
        super.init(initialViewState: MessagesScreenViewState(userID: userSession.clientProxy.userID,
                                                             terminology: .init(scenario: appSettings.terminologyScenario)),
                   mediaProvider: userSession.mediaProvider)
        
        userSession.clientProxy.userAvatarURLPublisher
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.userAvatarURL, on: self)
            .store(in: &cancellables)
        
        userSession.clientProxy.userDisplayNamePublisher
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.userDisplayName, on: self)
            .store(in: &cancellables)
        
        roomSummaryProvider.roomListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summaries in
                self?.updateRooms(with: summaries)
            }
            .store(in: &cancellables)
        
        appSettings.terminologyScenarioPublisher
            .sink { [weak self] scenario in
                self?.state.terminology = .init(scenario: scenario)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public
    
    override func process(viewAction: MessagesScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .selectRoom(let roomIdentifier):
            actionsSubject.send(.presentRoom(roomID: roomIdentifier))
        case .showSettings:
            actionsSubject.send(.showSettings)
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
