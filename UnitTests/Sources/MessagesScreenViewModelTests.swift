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
struct MessagesScreenViewModelTests {
    @Test
    func providerUpdatesAreReflectedInState() async throws {
        let (viewModel, roomsSubject) = makeViewModel(rooms: [])

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.rooms)) { $0.count == 2 }
        roomsSubject.send([Self.roomA, Self.roomB])
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.rooms.count == 2)
    }

    @Test
    func selectingRoomPresentsIt() async throws {
        let (viewModel, _) = makeViewModel(rooms: [Self.roomA])

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            action == .presentRoom(roomID: Self.roomA.id)
        }
        viewModel.context.send(viewAction: .selectRoom(roomIdentifier: Self.roomA.id))
        try await deferred.fulfill()
    }

    // MARK: - Helpers

    private static let roomA = RoomSummary.mock(id: "!a:example.com", name: "Alice")
    private static let roomB = RoomSummary.mock(id: "!b:example.com", name: "Bob")

    private func makeViewModel(rooms: [RoomSummary]) -> (MessagesScreenViewModel, CurrentValueSubject<[RoomSummary], Never>) {
        let roomsSubject = CurrentValueSubject<[RoomSummary], Never>(rooms)
        let roomSummaryProvider = RoomSummaryProviderMock(.init())
        roomSummaryProvider.underlyingRoomListPublisher = roomsSubject.asCurrentValuePublisher()
        let viewModel = MessagesScreenViewModel(roomSummaryProvider: roomSummaryProvider,
                                                appSettings: .volatile(),
                                                mediaProvider: MediaProviderMock(.init()))
        return (viewModel, roomsSubject)
    }
}
