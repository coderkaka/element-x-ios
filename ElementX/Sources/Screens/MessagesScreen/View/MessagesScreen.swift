//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct MessagesScreen: View {
    @Bindable var context: MessagesScreenViewModel.Context
    
    var body: some View {
        Group {
            if context.viewState.rooms.isEmpty {
                emptyState
            } else {
                roomList
            }
        }
        .navigationTitle(UntranslatedL10n.screenHomeTabMessages)
    }
    
    private var roomList: some View {
        List {
            ForEach(context.viewState.rooms) { room in
                HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: context.mediaProvider) { action in
                    if case .selectRoom(let roomIdentifier) = action {
                        context.send(viewAction: .selectRoom(roomIdentifier: roomIdentifier))
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            CompoundIcon(\.chat, size: .medium, relativeTo: .compound.bodyLG)
                .foregroundColor(.compound.iconSecondary)
                .accessibilityHidden(true)
            Text(UntranslatedL10n.screenMessagesEmpty)
                .font(.compound.bodyLG)
                .foregroundColor(.compound.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
    }
}

// MARK: - Previews

struct MessagesScreen_Previews: PreviewProvider, TestablePreview {
    static let emptyViewModel = makeViewModel(rooms: [])
    static let populatedViewModel = makeViewModel(rooms: .mockRooms)
    
    static var previews: some View {
        ElementNavigationStack {
            MessagesScreen(context: emptyViewModel.context)
        }
        .previewDisplayName("Empty")
        
        ElementNavigationStack {
            MessagesScreen(context: populatedViewModel.context)
        }
        .previewDisplayName("Populated")
    }
    
    static func makeViewModel(rooms: [RoomSummary]) -> MessagesScreenViewModel {
        let roomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded(rooms)))
        return MessagesScreenViewModel(roomSummaryProvider: roomSummaryProvider,
                                       appSettings: .volatile(),
                                       mediaProvider: MediaProviderMock(.init()))
    }
}
