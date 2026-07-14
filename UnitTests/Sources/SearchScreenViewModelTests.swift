//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
import Testing

@MainActor
struct SearchScreenViewModelTests {
    let viewModel: SearchScreenViewModelProtocol
    let messageSearchProxy: MessageSearchProxyMock
    let messageResultsSubject: CurrentValueSubject<[MessageSearchResultItem], Never>
    var context: SearchScreenViewModelType.Context {
        viewModel.context
    }
    
    init() {
        messageResultsSubject = CurrentValueSubject([])
        
        messageSearchProxy = MessageSearchProxyMock()
        messageSearchProxy.underlyingResultsPublisher = messageResultsSubject.asCurrentValuePublisher()
        messageSearchProxy.underlyingPaginationStatePublisher = .init(.idle(endReached: true))
        messageSearchProxy.searchQueryReturnValue = .success(())
        messageSearchProxy.paginateReturnValue = .success(())
        
        viewModel = SearchScreenViewModel(roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(.mockRooms))),
                                          messageSearchProxy: messageSearchProxy,
                                          mediaProvider: MediaProviderMock(.init()))
    }
    
    @Test
    func searching() async throws {
        let deferred = deferFulfillment(context.observe(\.viewState.rooms)) { $0.count == 1 }
        context.searchQuery = "Second"
        try await deferred.fulfill()
    }
    
    @Test
    func searchQueryIsForwardedToMessageSearch() async throws {
        let queriesSubject = PassthroughSubject<String, Never>()
        messageSearchProxy.searchQueryClosure = { query in
            queriesSubject.send(query)
            return .success(())
        }
        
        let deferred = deferFulfillment(queriesSubject) { $0 == "Second" }
        context.searchQuery = "Second"
        try await deferred.fulfill()
    }
    
    @Test
    func messageResultsArePublished() async throws {
        let result = MessageSearchResultItem(eventID: "$1", roomID: "2", roomName: nil, sender: .test, body: AttributedString("Hello"), timestamp: .now)
        let deferred = deferFulfillment(context.observe(\.viewState.messageResults)) { $0.count == 1 }
        messageResultsSubject.send([result])
        try await deferred.fulfill()
        #expect(context.viewState.messageResults.first?.eventID == "$1")
    }
    
    @Test
    func roomSelection() async throws {
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            switch action {
            case .presentRoom(let roomID, let eventID):
                roomID == "2" && eventID == nil
            case .cancel:
                false
            }
        }
        
        context.send(viewAction: .selectRoom(roomID: "2"))
        
        try await deferred.fulfill()
    }
    
    @Test
    func messageResultSelection() async throws {
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            switch action {
            case .presentRoom(let roomID, let eventID):
                roomID == "2" && eventID == "$1"
            case .cancel:
                false
            }
        }
        
        context.send(viewAction: .selectMessageResult(roomID: "2", eventID: "$1"))
        
        try await deferred.fulfill()
    }
    
    @Test
    func cancel() async throws {
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            switch action {
            case .cancel:
                true
            default:
                false
            }
        }
        
        context.send(viewAction: .cancel)
        
        try await deferred.fulfill()
    }
}
