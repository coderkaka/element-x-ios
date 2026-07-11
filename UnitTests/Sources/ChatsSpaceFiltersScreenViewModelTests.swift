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
final class ChatsSpaceFiltersScreenViewModelTests {
    var cancellables = Set<AnyCancellable>()
    
    // MARK: - Actions (fix-spacebar3 contract A/C)
    
    @Test
    func confirmingAFilterForwardsIt() async throws {
        let (viewModel, _) = makeViewModel()
        let filter = Self.filters[0]
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .confirm(filter) }
        viewModel.context.send(viewAction: .confirm(filter))
        try await deferred.fulfill()
    }
    
    @Test
    func confirmingAllForwardsNil() async throws {
        let (viewModel, _) = makeViewModel()
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .confirm(nil) }
        viewModel.context.send(viewAction: .confirm(nil))
        try await deferred.fulfill()
    }
    
    @Test
    func manageSpacesForwardsTheAction() async throws {
        let (viewModel, _) = makeViewModel()
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .manageSpaces }
        viewModel.context.send(viewAction: .manageSpaces)
        try await deferred.fulfill()
    }
    
    @Test
    func cancelForwardsTheAction() async throws {
        let (viewModel, _) = makeViewModel()
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .cancel }
        viewModel.context.send(viewAction: .cancel)
        try await deferred.fulfill()
    }
    
    // MARK: - Selection state ("全部" row + per-filter checkmark, contract C)
    
    @Test
    func isAllFiltersSelectedReflectsTheAppSettingsSelection() {
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(appSettings: appSettings)
        #expect(viewModel.context.viewState.isAllFiltersSelected)
        
        appSettings.selectedSpaceFilterRoomID = "space1"
        #expect(!viewModel.context.viewState.isAllFiltersSelected)
        
        appSettings.selectedSpaceFilterRoomID = nil
        #expect(viewModel.context.viewState.isAllFiltersSelected)
    }
    
    // MARK: - Reordering, moved from the retired chip bar into the panel (contract D)
    
    @Test
    func reorderSwapsAdjacentTopLevelFiltersInAppSettings() {
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(appSettings: appSettings)
        
        viewModel.context.send(viewAction: .reorder(roomID: "space2", direction: .left))
        
        #expect(appSettings.spaceFilterOrder == ["space2", "space1", "space3"])
        #expect(viewModel.context.viewState.topLevelFilterIDsInOrder == ["space2", "space1", "space3"])
    }
    
    @Test
    func reorderAtTheLeadingEdgeIsANoOp() {
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(appSettings: appSettings)
        
        viewModel.context.send(viewAction: .reorder(roomID: "space1", direction: .left))
        
        #expect(appSettings.spaceFilterOrder.isEmpty)
    }
    
    @Test
    func reorderCarriesDescendantsAlongWithTheirParent() {
        // "space1" has a nested child ("space1-child") immediately after it in provider order —
        // moving "space2" ahead of "space1" must not separate "space1" from its own child.
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init([
            .init(room: .mock(id: "space1", isSpace: true), level: 0, descendants: ["space1-child"]),
            .init(room: .mock(id: "space1-child", isSpace: true), level: 1, descendants: []),
            .init(room: .mock(id: "space2", isSpace: true), level: 0, descendants: [])
        ])
        let appSettings: AppSettings = .volatile()
        let viewModel = ChatsSpaceFiltersScreenViewModel(spaceService: spaceService,
                                                         appSettings: appSettings,
                                                         hasPendingSpaceInvites: false,
                                                         mediaProvider: MediaProviderMock(.init()))
        
        viewModel.context.send(viewAction: .reorder(roomID: "space2", direction: .left))
        
        #expect(viewModel.context.viewState.orderedFilters.map(\.room.id) == ["space2", "space1", "space1-child"])
    }
    
    // MARK: - Live updates from AppSettings
    
    @Test
    func spaceFilterOrderAndSelectionStayLiveWithAppSettings() async throws {
        let appSettings: AppSettings = .volatile()
        let (viewModel, _) = makeViewModel(appSettings: appSettings)
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.selectedSpaceFilterRoomID)) { $0 == "space3" }
        appSettings.selectedSpaceFilterRoomID = "space3"
        try await deferred.fulfill()
        
        let orderDeferred = deferFulfillment(viewModel.context.observe(\.viewState.spaceFilterOrder)) { $0 == ["space3", "space2", "space1"] }
        appSettings.spaceFilterOrder = ["space3", "space2", "space1"]
        try await orderDeferred.fulfill()
    }
    
    // MARK: - Pending invites badge fallback (contract C's V1)
    
    @Test
    func hasPendingSpaceInvitesReflectsTheConstructorParameter() {
        let (viewModel, _) = makeViewModel(hasPendingSpaceInvites: true)
        #expect(viewModel.context.viewState.hasPendingSpaceInvites)
    }
    
    // MARK: - Helpers
    
    private static var filters: [SpaceServiceFilter] {
        [
            .init(room: .mock(id: "space1", isSpace: true), level: 0, descendants: []),
            .init(room: .mock(id: "space2", isSpace: true), level: 0, descendants: []),
            .init(room: .mock(id: "space3", isSpace: true), level: 0, descendants: [])
        ]
    }
    
    private func makeViewModel(appSettings: AppSettings = .volatile(),
                               hasPendingSpaceInvites: Bool = false) -> (ChatsSpaceFiltersScreenViewModel, SpaceServiceProxyMock) {
        let spaceService = SpaceServiceProxyMock()
        spaceService.underlyingSpaceFilterPublisher = .init(Self.filters)
        let viewModel = ChatsSpaceFiltersScreenViewModel(spaceService: spaceService,
                                                         appSettings: appSettings,
                                                         hasPendingSpaceInvites: hasPendingSpaceInvites,
                                                         mediaProvider: MediaProviderMock(.init()))
        return (viewModel, spaceService)
    }
}

@MainActor
extension ChatsSpaceFiltersScreenViewModelAction: @MainActor @retroactive Equatable {
    public static func == (lhs: ChatsSpaceFiltersScreenViewModelAction, rhs: ChatsSpaceFiltersScreenViewModelAction) -> Bool {
        switch (lhs, rhs) {
        case (.confirm(let lhsFilter), .confirm(let rhsFilter)):
            lhsFilter == rhsFilter
        case (.manageSpaces, .manageSpaces):
            true
        case (.cancel, .cancel):
            true
        default:
            false
        }
    }
}

struct SortSpaceFilterTreeTests {
    private static var filters: [SpaceServiceFilter] {
        [
            .init(room: .mock(id: "space1", isSpace: true), level: 0, descendants: ["space1-child"]),
            .init(room: .mock(id: "space1-child", isSpace: true), level: 1, descendants: []),
            .init(room: .mock(id: "space2", isSpace: true), level: 0, descendants: []),
            .init(room: .mock(id: "space3", isSpace: true), level: 0, descendants: ["space3-child"]),
            .init(room: .mock(id: "space3-child", isSpace: true), level: 1, descendants: [])
        ]
    }
    
    @Test
    func emptyOrderKeepsProviderOrder() {
        let sorted = sortSpaceFilterTree(Self.filters, byOrder: [])
        #expect(sorted.map(\.room.id) == ["space1", "space1-child", "space2", "space3", "space3-child"])
    }
    
    @Test
    func reorderingTopLevelEntriesCarriesTheirDescendantsAlong() {
        let sorted = sortSpaceFilterTree(Self.filters, byOrder: ["space3", "space1"])
        #expect(sorted.map(\.room.id) == ["space3", "space3-child", "space1", "space1-child", "space2"])
    }
    
    @Test
    func unknownIDsInOrderHaveNoEffect() {
        let sorted = sortSpaceFilterTree(Self.filters, byOrder: ["not-a-real-space", "space2"])
        #expect(sorted.map(\.room.id) == ["space2", "space1", "space1-child", "space3", "space3-child"])
    }
}
