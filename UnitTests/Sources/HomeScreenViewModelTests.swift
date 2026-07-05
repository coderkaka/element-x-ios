//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Testing

@MainActor
final class HomeScreenViewModelTests {
    var viewModel: HomeScreenViewModelProtocol!
    var context: HomeScreenViewModelType.Context! {
        viewModel.context
    }
    
    var clientProxy: ClientProxyMock!
    var roomSummaryProvider: RoomSummaryProviderMock!
    var notificationManager: NotificationManagerMock!
    var agentTaskIndexService: AgentTaskIndexServiceMock!
    var agentProjectIndexService: AgentProjectIndexServiceMock!
    private let appSettings: AppSettings
    
    var cancellables = Set<AnyCancellable>()
    
    init() {
        appSettings = AppSettings.volatile()
    }
    
    @Test
    func selectRoom() async {
        setupViewModel()
        
        let mockRoomID = "mock_room_id"
        var correctResult = false
        var selectedRoomID = ""
        
        viewModel.actions
            .sink { action in
                switch action {
                case .presentRoom(let roomID):
                    correctResult = true
                    selectedRoomID = roomID
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        context.send(viewAction: .selectRoom(roomIdentifier: mockRoomID))
        await Task.yield()
        #expect(correctResult)
        #expect(mockRoomID == selectedRoomID)
    }
    
    @Test
    func tapUserAvatar() async {
        setupViewModel()
        
        var correctResult = false
        
        viewModel.actions
            .sink { action in
                switch action {
                case .presentSettingsScreen:
                    correctResult = true
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        context.send(viewAction: .showSettings)
        await Task.yield()
        #expect(correctResult)
    }
    
    @Test
    func leaveRoomAlert() async throws {
        setupViewModel()
        
        let mockRoomID = "1"
        
        clientProxy.roomForIdentifierClosure = { _ in .joined(JoinedRoomProxyMock(.init(id: mockRoomID, name: "Some room"))) }
        
        let deferred = deferFulfillment(context.$viewState) { value in
            value.bindings.leaveRoomAlertItem != nil
        }
        
        context.send(viewAction: .leaveRoom(roomIdentifier: mockRoomID))
        
        try await deferred.fulfill()
        
        #expect(context.leaveRoomAlertItem?.roomID == mockRoomID)
    }
    
    @Test
    func leaveRoomError() async throws {
        setupViewModel()
        
        let mockRoomID = "1"
        let room = JoinedRoomProxyMock(.init(id: mockRoomID, name: "Some room"))
        room.leaveRoomClosure = { .failure(.sdkError(ClientProxyMockError.generic)) }
        
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }
        
        let deferred = deferFulfillment(context.$viewState) { value in
            value.bindings.alertInfo != nil
        }
        
        context.send(viewAction: .confirmLeaveRoom(roomIdentifier: mockRoomID))
        
        try await deferred.fulfill()
        
        #expect(context.alertInfo != nil)
    }
    
    @Test
    func leaveRoomSuccess() async throws {
        setupViewModel()
        
        let mockRoomID = "1"
        
        let room = JoinedRoomProxyMock(.init(id: mockRoomID, name: "Some room"))
        room.leaveRoomClosure = { .success(()) }
        
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }
        
        let deferred = deferFulfillment(viewModel.actions) { action in
            if case .roomLeft(let roomIdentifier) = action {
                return roomIdentifier == mockRoomID
            }
            return false
        }
        
        context.send(viewAction: .confirmLeaveRoom(roomIdentifier: mockRoomID))
        try await deferred.fulfill()
        #expect(context.alertInfo == nil)
    }
    
    @Test
    func showRoomDetails() async {
        setupViewModel()
        
        let mockRoomID = "1"
        var correctResult = false
        viewModel.actions
            .sink { action in
                switch action {
                case .presentRoomDetails(let roomIdentifier):
                    correctResult = roomIdentifier == mockRoomID
                default:
                    break
                }
            }
            .store(in: &cancellables)
        context.send(viewAction: .showRoomDetails(roomIdentifier: mockRoomID))
        await Task.yield()
        #expect(context.alertInfo == nil)
        #expect(correctResult)
    }
    
    @Test
    func filters() async throws {
        setupViewModel()
        
        // 政事 (chats tab) always excludes DMs: `.rooms` is force-applied and a (still technically
        // possible) `.people` filter is stripped before the filter reaches the provider.
        context.filtersState.activateFilter(.people)
        try await Task.sleep(for: .milliseconds(100))
        #expect(roomSummaryProvider.setFilterReceivedFilter == .all(filters: [.rooms]))
        #expect(roomSummaryProvider.roomListPublisher.value.allSatisfy { !$0.isDirect })
    }
    
    @Test
    func defaultFilterExcludesDirectMessages() async throws {
        setupViewModel()
        
        // Even with no user-selected filter active, 政事 must still only ask the provider for group rooms.
        try await Task.sleep(for: .milliseconds(100))
        #expect(roomSummaryProvider.setFilterReceivedFilter == .all(filters: [.rooms]))
    }
    
    @Test
    func search() async throws {
        setupViewModel()
        
        context.isSearchFieldFocused = true
        context.searchQuery = "lude to Found"
        try await Task.sleep(for: .milliseconds(100))
        #expect(roomSummaryProvider.roomListPublisher.value.first?.name == "Prelude to Foundation")
        #expect(roomSummaryProvider.roomListPublisher.value.count == 1)
    }
    
    @Test
    func filtersEmptyState() async throws {
        setupViewModel()
        
        context.filtersState.activateFilter(.people)
        context.filtersState.activateFilter(.favourites)
        try await Task.sleep(for: .milliseconds(100))
        #expect(context.viewState.shouldShowEmptyFilterState)
        context.isSearchFieldFocused = true
        #expect(!context.viewState.shouldShowEmptyFilterState)
    }
    
    @Test
    func setUpRecoveryBannerState() async throws {
        // Given a view model without a visible security banner.
        let securityStateStateSubject = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .verified, recoveryState: .unknown))
        setupViewModel(securityStatePublisher: securityStateStateSubject.asCurrentValuePublisher())
        #expect(context.viewState.securityBannerMode == .none)
        
        // When the recovery state comes through as disabled.
        var deferred = deferFulfillment(context.$viewState) { $0.requiresExtraAccountSetup == true }
        securityStateStateSubject.send(.init(verificationState: .verified, recoveryState: .disabled))
        try await deferred.fulfill()
        
        // Then the banner should be shown to set up recovery.
        #expect(context.viewState.securityBannerMode == .show(.setUpRecovery))
        
        // When the recovery is enabled.
        deferred = deferFulfillment(context.$viewState) { $0.requiresExtraAccountSetup == false }
        securityStateStateSubject.send(.init(verificationState: .verified, recoveryState: .enabled))
        try await deferred.fulfill()
        
        // Then the banner should no longer be shown.
        #expect(context.viewState.securityBannerMode == .none)
    }
    
    @Test
    func dismissSetUpRecoveryBannerState() async throws {
        // Given a view model with the setup recovery banner shown.
        let securityStateStateSubject = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .verified, recoveryState: .unknown))
        setupViewModel(securityStatePublisher: securityStateStateSubject.asCurrentValuePublisher())
        var deferred = deferFulfillment(context.$viewState) { $0.securityBannerMode == .show(.setUpRecovery) }
        securityStateStateSubject.send(.init(verificationState: .verified, recoveryState: .disabled))
        try await deferred.fulfill()
        
        // When the banner is dismissed.
        deferred = deferFulfillment(context.$viewState) { $0.securityBannerMode == .dismissed }
        context.send(viewAction: .skipRecoveryKeyConfirmation)
        
        // Then the banner should no longer be shown.
        try await deferred.fulfill()
        
        // And when the recovery state comes through a second time the banner should still not be shown.
        let failure = deferFailure(context.$viewState, timeout: .seconds(1)) { $0.securityBannerMode != .dismissed }
        securityStateStateSubject.send(.init(verificationState: .verified, recoveryState: .disabled))
        try await failure.fulfill()
    }
    
    @Test
    func outOfSyncRecoveryBannerState() async throws {
        // Given a view model without a visible security banner.
        let securityStateStateSubject = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .verified, recoveryState: .unknown))
        setupViewModel(securityStatePublisher: securityStateStateSubject.asCurrentValuePublisher())
        #expect(context.viewState.securityBannerMode == .none)
        
        // When the recovery state comes through as incomplete.
        var deferred = deferFulfillment(context.$viewState) { $0.requiresExtraAccountSetup == true }
        securityStateStateSubject.send(.init(verificationState: .verified, recoveryState: .incomplete))
        try await deferred.fulfill()
        
        // Then the banner should be shown for out of sync recovery.
        #expect(context.viewState.securityBannerMode == .show(.recoveryOutOfSync))
        
        // When the recovery is enabled.
        deferred = deferFulfillment(context.$viewState) { $0.requiresExtraAccountSetup == false }
        securityStateStateSubject.send(.init(verificationState: .verified, recoveryState: .enabled))
        try await deferred.fulfill()
        
        // Then the banner should no longer be shown.
        #expect(context.viewState.securityBannerMode == .none)
    }
    
    @Test
    func inviteUnreadBadge() async throws {
        setupViewModel(invites: .rooms)
        var invites = context.viewState.rooms.invites
        #expect(invites.count == 2)
        
        for invite in invites {
            #expect(invite.badges.isDotShown)
        }
        
        let deferred = deferFulfillment(context.$viewState) { state in
            state.rooms.contains { room in
                room.roomID == invites[0].roomID && room.badges.isDotShown == false
            }
        }
        appSettings.seenInvites = Set(invites.compactMap(\.roomID))
        try await deferred.fulfill()
        invites = context.viewState.rooms.invites
        
        for invite in invites {
            #expect(!invite.badges.isDotShown)
        }
    }
    
    @Test
    func acceptInvite() async throws {
        setupViewModel(invites: .rooms)
        
        let invitedRoomIDs = context.viewState.rooms.invites.compactMap(\.roomID)
        appSettings.seenInvites = Set(invitedRoomIDs)
        #expect(invitedRoomIDs.count == 2)
        
        let deferred = deferFulfillment(viewModel.actions) { $0 == .presentRoom(roomIdentifier: invitedRoomIDs[0]) }
        context.send(viewAction: .acceptInvite(roomIdentifier: invitedRoomIDs[0]))
        try await deferred.fulfill()
        
        #expect(appSettings.seenInvites == [invitedRoomIDs[1]])
        #expect(!notificationManager.removeDeliveredMessageNotificationsForCalled, "The notification will be dismissed when opening the room.")
    }
    
    @Test
    func acceptSpaceInvite() async throws {
        setupViewModel(invites: .spaces)
        
        let invitedRoomIDs = context.viewState.rooms.invites.compactMap(\.roomID)
        appSettings.seenInvites = Set(invitedRoomIDs)
        #expect(invitedRoomIDs.count == 2)
        
        let deferred = deferFulfillment(viewModel.actions) {
            $0 == .presentSpace(SpaceRoomListProxyMock(.init(spaceServiceRoom: SpaceServiceRoom.mock(id: invitedRoomIDs[0], isSpace: true))))
        }
        context.send(viewAction: .acceptInvite(roomIdentifier: invitedRoomIDs[0]))
        try await deferred.fulfill()
        
        #expect(appSettings.seenInvites == [invitedRoomIDs[1]])
        #expect(!notificationManager.removeDeliveredMessageNotificationsForCalled, "The notification will be dismissed when opening the room.")
    }
    
    @Test
    func declineInvite() async throws {
        setupViewModel(invites: .rooms)
        let invitedRoomIDs = context.viewState.rooms.invites.compactMap(\.roomID)
        appSettings.seenInvites = Set(invitedRoomIDs)
        #expect(invitedRoomIDs.count == 2)
        
        let deferred = deferFulfillment(context.$viewState) { $0.bindings.alertInfo != nil }
        context.send(viewAction: .declineInvite(roomIdentifier: invitedRoomIDs[0]))
        try await deferred.fulfill()
        
        var rejectCalled = false
        clientProxy.roomForIdentifierClosure = { _ in
            let roomProxy = InvitedRoomProxyMock(.init())
            roomProxy.rejectInvitationClosure = {
                rejectCalled = true
                return .success(())
            }
            
            return .invited(roomProxy)
        }
        context.viewState.bindings.alertInfo?.verticalButtons?[0].action?()
        
        // Wait for the async action to complete
        try await Task.sleep(for: .milliseconds(100))
        #expect(rejectCalled)
        
        #expect(appSettings.seenInvites == [invitedRoomIDs[1]])
        #expect(notificationManager.removeDeliveredMessageNotificationsForCalled)
        #expect(notificationManager.removeDeliveredMessageNotificationsForReceivedInvocations == [invitedRoomIDs[0]])
    }
    
    @Test
    func declineAndBlockInvite() async throws {
        setupViewModel(invites: .rooms)
        let invitedRoomIDs = context.viewState.rooms.invites.compactMap(\.roomID)
        appSettings.seenInvites = Set(invitedRoomIDs)
        #expect(invitedRoomIDs.count == 2)
        
        let deferred = deferFulfillment(context.$viewState) { $0.bindings.alertInfo != nil }
        context.send(viewAction: .declineInvite(roomIdentifier: invitedRoomIDs[0]))
        try await deferred.fulfill()
        
        let deferredAction = deferFulfillment(viewModel.actions) { $0 == .presentDeclineAndBlock(userID: RoomMemberProxyMock.mockCharlie.userID, roomID: invitedRoomIDs[0]) }
        context.viewState.bindings.alertInfo?.secondaryButton?.action?()
        try await deferredAction.fulfill()
    }
    
    @Test
    func agentTaskAndPendingChoiceCountsJoinRooms() async throws {
        let tasks = [
            AgentTaskSummary(roomID: "2", roomName: "Foundation and Empire", taskID: "t1", title: "A", isResolved: false, doneStepCount: 0, totalStepCount: 1),
            AgentTaskSummary(roomID: "2", roomName: "Foundation and Empire", taskID: "t2", title: "B", isResolved: false, doneStepCount: 0, totalStepCount: 1),
            AgentTaskSummary(roomID: "2", roomName: "Foundation and Empire", taskID: "t3", title: "C", isResolved: true, doneStepCount: 1, totalStepCount: 1)
        ]
        let projects = [AgentProjectSummary(roomID: "3", name: "Second Foundation Plan", description: nil, status: .active)]
        let pendingChoices = [AgentPendingChoiceSummary(roomID: "4", eventID: "$choice1", question: "Proceed?")]
        
        setupViewModel(tasks: tasks, projects: projects, pendingChoices: pendingChoices)
        
        let deferred = deferFulfillment(context.$viewState) { state in
            state.rooms.first { $0.roomID == "2" }?.activeTaskCount == 2
        }
        try await deferred.fulfill()
        
        let room2 = try #require(context.viewState.rooms.first { $0.roomID == "2" })
        #expect(room2.activeTaskCount == 2)
        #expect(room2.doneTaskCount == 1)
        #expect(room2.totalTaskCount == 3)
        #expect(!room2.isProject)
        #expect(room2.pendingChoiceCount == 0)
        
        let room3 = try #require(context.viewState.rooms.first { $0.roomID == "3" })
        #expect(room3.isProject)
        #expect(room3.activeTaskCount == 0)
        #expect(room3.totalTaskCount == 0)
        
        let room4 = try #require(context.viewState.rooms.first { $0.roomID == "4" })
        #expect(room4.pendingChoiceCount == 1)
        #expect(!room4.isProject)
        
        // A room untouched by any of the three publishers keeps every count at its zero default.
        let room1 = try #require(context.viewState.rooms.first { $0.roomID == "1" })
        #expect(room1.activeTaskCount == 0)
        #expect(room1.doneTaskCount == 0)
        #expect(room1.pendingChoiceCount == 0)
        #expect(!room1.isProject)
    }
    
    @Test
    func agentPrioritySortingPutsPendingFirstThenActiveThenRestPreservingProviderOrder() async throws {
        // Provider order for group rooms (DMs "5"/"6" excluded by the .rooms filter) is: 1, 2, 3, 4, 7, 0.
        // Room "4" is last in that order but carries a pending choice, so it must sort first.
        // Rooms "2" and "3" carry active tasks and must both come next, keeping their relative
        // provider order (2 before 3) since the re-sort is a stable, filter-based grouping.
        let tasks = [
            AgentTaskSummary(roomID: "2", roomName: "Foundation and Empire", taskID: "t1", title: nil, isResolved: false, doneStepCount: 0, totalStepCount: 1),
            AgentTaskSummary(roomID: "3", roomName: "Second Foundation", taskID: "t2", title: nil, isResolved: false, doneStepCount: 0, totalStepCount: 1)
        ]
        let pendingChoices = [AgentPendingChoiceSummary(roomID: "4", eventID: "$choice1", question: nil)]
        
        setupViewModel(tasks: tasks, pendingChoices: pendingChoices)
        
        let deferred = deferFulfillment(context.$viewState) { state in
            state.rooms.first?.roomID == "4"
        }
        try await deferred.fulfill()
        
        let orderedRoomIDs = context.viewState.rooms.compactMap(\.roomID)
        #expect(orderedRoomIDs == ["4", "2", "3", "1", "7", "0"])
    }
    
    @Test
    func pendingChoicesStripJoinsRoomNamesAndDegradesGracefully() async throws {
        let pendingChoices = [
            AgentPendingChoiceSummary(roomID: "4", eventID: "$choice1", question: "Proceed?"),
            AgentPendingChoiceSummary(roomID: "not-in-provider", eventID: "$choice2", question: "Ship it?")
        ]
        
        setupViewModel(pendingChoices: pendingChoices)
        
        let deferred = deferFulfillment(context.$viewState) { $0.pendingChoices.count == 2 }
        try await deferred.fulfill()
        
        let joined = try #require(context.viewState.pendingChoices.first { $0.roomID == "4" })
        #expect(joined.roomName == "Foundation's Edge")
        
        // A pending choice whose room isn't in the (possibly filtered/paginated) provider list
        // must still surface in the strip/sheet, just without a resolvable room name.
        let orphan = try #require(context.viewState.pendingChoices.first { $0.roomID == "not-in-provider" })
        #expect(orphan.roomName == nil)
    }
    
    @Test
    func pendingChoicesStripIntersectsWithSpaceFilter() async throws {
        let pendingChoices = [
            AgentPendingChoiceSummary(roomID: "2", eventID: "$choice1", question: "A"),
            AgentPendingChoiceSummary(roomID: "4", eventID: "$choice2", question: "B")
        ]
        
        setupViewModel(pendingChoices: pendingChoices)
        
        let deferred = deferFulfillment(context.$viewState) { $0.pendingChoices.count == 2 }
        try await deferred.fulfill()
        
        let spaceFilter = SpaceServiceFilter(room: .mock(id: "space1", isSpace: true), level: 0, descendants: ["4"])
        let filteredDeferred = deferFulfillment(context.$viewState) { $0.pendingChoices.count == 1 }
        context.send(viewAction: .selectSpaceFilter(spaceFilter))
        try await filteredDeferred.fulfill()
        
        #expect(context.viewState.pendingChoices.map(\.roomID) == ["4"])
    }
    
    @Test
    func tappedPendingChoicesStripWithSinglePendingOpensRoomDirectly() async throws {
        let pendingChoices = [AgentPendingChoiceSummary(roomID: "4", eventID: "$choice1", question: "Proceed?")]
        setupViewModel(pendingChoices: pendingChoices)
        
        let deferred = deferFulfillment(context.$viewState) { $0.pendingChoices.count == 1 }
        try await deferred.fulfill()
        
        let deferredAction = deferFulfillment(viewModel.actions) { $0 == .presentRoom(roomIdentifier: "4") }
        context.send(viewAction: .tappedPendingChoicesStrip)
        try await deferredAction.fulfill()
        
        #expect(!context.viewState.bindings.isPresentingPendingChoices)
    }
    
    @Test
    func tappedPendingChoicesStripWithMultiplePendingOpensSheet() async throws {
        let pendingChoices = [
            AgentPendingChoiceSummary(roomID: "2", eventID: "$choice1", question: "A"),
            AgentPendingChoiceSummary(roomID: "4", eventID: "$choice2", question: "B")
        ]
        setupViewModel(pendingChoices: pendingChoices)
        
        let deferred = deferFulfillment(context.$viewState) { $0.pendingChoices.count == 2 }
        try await deferred.fulfill()
        
        #expect(!context.viewState.bindings.isPresentingPendingChoices)
        context.send(viewAction: .tappedPendingChoicesStrip)
        #expect(context.viewState.bindings.isPresentingPendingChoices)
    }
    
    @Test
    func selectPendingChoiceClosesSheetAndOpensRoom() async throws {
        let pendingChoices = [
            AgentPendingChoiceSummary(roomID: "2", eventID: "$choice1", question: "A"),
            AgentPendingChoiceSummary(roomID: "4", eventID: "$choice2", question: "B")
        ]
        setupViewModel(pendingChoices: pendingChoices)
        
        let deferred = deferFulfillment(context.$viewState) { $0.pendingChoices.count == 2 }
        try await deferred.fulfill()
        
        context.send(viewAction: .tappedPendingChoicesStrip)
        #expect(context.viewState.bindings.isPresentingPendingChoices)
        
        let deferredAction = deferFulfillment(viewModel.actions) { $0 == .presentRoom(roomIdentifier: "4") }
        context.send(viewAction: .selectPendingChoice(roomID: "4"))
        try await deferredAction.fulfill()
        
        #expect(!context.viewState.bindings.isPresentingPendingChoices)
    }
    
    @Test
    func newSoundBanner() {
        appSettings.hasSeenNewSoundBanner = false
        
        setupViewModel()
        #expect(context.viewState.shouldShowBanner)
        #expect(context.viewState.shouldShowNewSoundBanner)
        
        context.send(viewAction: .dismissNewSoundBanner)
        #expect(!context.viewState.shouldShowBanner)
        #expect(!context.viewState.shouldShowNewSoundBanner)
        #expect(appSettings.hasSeenNewSoundBanner)
    }
    
    // MARK: - Space Filter Persistence (F)
    
    @Test
    func restoresPersistedSpaceFilterOnFirstAvailableFiltersEmission() async throws {
        // Given a persisted 道 selection from a previous launch.
        appSettings.selectedSpaceFilterRoomID = "space2"
        let filterSubject = CurrentValueSubject<[SpaceServiceFilter], Never>([])
        setupViewModel(spaceFilterSubject: filterSubject)
        #expect(context.viewState.selectedSpaceFilter == nil)
        
        // When the space list becomes available for the first time.
        let deferred = deferFulfillment(context.$viewState) { $0.selectedSpaceFilter != nil }
        filterSubject.send(Self.levelZeroSpaceFilters)
        try await deferred.fulfill()
        
        // Then the persisted selection should be restored automatically.
        #expect(context.viewState.selectedSpaceFilter?.room.id == "space2")
    }
    
    @Test
    func selectingAllClearsPersistenceAndIsNotReRestored() async throws {
        appSettings.selectedSpaceFilterRoomID = "space2"
        let filterSubject = CurrentValueSubject<[SpaceServiceFilter], Never>(Self.levelZeroSpaceFilters)
        setupViewModel(spaceFilterSubject: filterSubject)
        
        let restoredDeferred = deferFulfillment(context.$viewState) { $0.selectedSpaceFilter != nil }
        try await restoredDeferred.fulfill()
        #expect(context.viewState.selectedSpaceFilter?.room.id == "space2")
        
        // When the user explicitly returns to 全部.
        let clearedDeferred = deferFulfillment(context.$viewState) { $0.selectedSpaceFilter == nil }
        context.send(viewAction: .selectSpaceFilter(nil))
        try await clearedDeferred.fulfill()
        #expect(appSettings.selectedSpaceFilterRoomID == nil)
        
        // Then a subsequent filters emission must not bounce the user back into their old 道.
        filterSubject.send(Self.levelZeroSpaceFilters)
        try await Task.sleep(for: .milliseconds(100))
        #expect(context.viewState.selectedSpaceFilter == nil)
    }
    
    @Test
    func stalePersistedSpaceFilterFallsBackToAll() async throws {
        // Given a persisted ID for a space the user is no longer (or never was) a member of.
        appSettings.selectedSpaceFilterRoomID = "no-longer-joined-space"
        let filterSubject = CurrentValueSubject<[SpaceServiceFilter], Never>([])
        setupViewModel(spaceFilterSubject: filterSubject)
        
        filterSubject.send(Self.levelZeroSpaceFilters)
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(context.viewState.selectedSpaceFilter == nil)
        #expect(appSettings.selectedSpaceFilterRoomID == nil)
    }
    
    // MARK: - Space Filter Reordering (G)
    
    @Test
    func reorderSpaceFilterMovesLeftAndRight() async throws {
        let filterSubject = CurrentValueSubject<[SpaceServiceFilter], Never>(Self.levelZeroSpaceFilters)
        setupViewModel(spaceFilterSubject: filterSubject)
        
        let deferred = deferFulfillment(context.$viewState) { !$0.availableSpaceFilters.isEmpty }
        try await deferred.fulfill()
        
        #expect(context.viewState.topLevelSpaceFilters.map(\.room.id) == ["space1", "space2", "space3", "space4", "space5", "space6", "space7"])
        
        context.send(viewAction: .reorderSpaceFilter(roomID: "space2", direction: .left))
        try await Task.sleep(for: .milliseconds(50))
        #expect(context.viewState.topLevelSpaceFilters.map(\.room.id) == ["space2", "space1", "space3", "space4", "space5", "space6", "space7"])
        #expect(appSettings.spaceFilterOrder == ["space2", "space1", "space3", "space4", "space5", "space6", "space7"])
        
        context.send(viewAction: .reorderSpaceFilter(roomID: "space2", direction: .right))
        try await Task.sleep(for: .milliseconds(50))
        #expect(context.viewState.topLevelSpaceFilters.map(\.room.id) == ["space1", "space2", "space3", "space4", "space5", "space6", "space7"])
    }
    
    @Test
    func reorderSpaceFilterClampsAtEdges() async throws {
        let filterSubject = CurrentValueSubject<[SpaceServiceFilter], Never>(Self.levelZeroSpaceFilters)
        setupViewModel(spaceFilterSubject: filterSubject)
        
        let deferred = deferFulfillment(context.$viewState) { !$0.availableSpaceFilters.isEmpty }
        try await deferred.fulfill()
        
        let originalOrder = context.viewState.topLevelSpaceFilters.map(\.room.id)
        
        // Moving the first chip left, or the last chip right, must be a no-op.
        context.send(viewAction: .reorderSpaceFilter(roomID: "space1", direction: .left))
        try await Task.sleep(for: .milliseconds(50))
        #expect(context.viewState.topLevelSpaceFilters.map(\.room.id) == originalOrder)
        
        context.send(viewAction: .reorderSpaceFilter(roomID: "space7", direction: .right))
        try await Task.sleep(for: .milliseconds(50))
        #expect(context.viewState.topLevelSpaceFilters.map(\.room.id) == originalOrder)
    }
    
    // MARK: - Helpers
    
    enum InviteType { case rooms, spaces }
    
    private func setupViewModel(securityStatePublisher: CurrentValuePublisher<SessionSecurityState, Never>? = nil,
                                invites: InviteType? = nil,
                                tasks: [AgentTaskSummary] = [],
                                projects: [AgentProjectSummary] = [],
                                pendingChoices: [AgentPendingChoiceSummary] = [],
                                spaceFilterSubject: CurrentValueSubject<[SpaceServiceFilter], Never>? = nil) {
        cancellables.removeAll()
        
        var rooms: [RoomSummary] = .mockRooms
        
        switch invites {
        case .rooms:
            rooms += .mockInvites
        case .spaces:
            rooms += .mockSpaceInvites
        case nil:
            break
        }
        
        roomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded(rooms)))
        
        clientProxy = ClientProxyMock(.init(userID: "@mock:client.com",
                                            roomSummaryProvider: roomSummaryProvider))
        
        clientProxy.joinRoomViaReturnValue = .success(())
        clientProxy.joinRoomAliasReturnValue = .success(())
        
        switch invites {
        case .rooms:
            clientProxy.roomForIdentifierClosure = { roomID in .invited(InvitedRoomProxyMock(.init(id: roomID))) }
        case .spaces:
            clientProxy.roomForIdentifierClosure = { spaceID in .invited(InvitedRoomProxyMock(.init(id: spaceID, isSpace: true))) }
            
            let spaceServiceProxy = SpaceServiceProxyMock(.init())
            spaceServiceProxy.spaceRoomListSpaceIDClosure = { spaceID in
                .success(SpaceRoomListProxyMock(.init(spaceServiceRoom: SpaceServiceRoom.mock(id: spaceID, isSpace: true))))
            }
            clientProxy.spaceService = spaceServiceProxy
        case nil:
            break
        }
        
        if let spaceFilterSubject {
            let spaceServiceProxy = SpaceServiceProxyMock(.init())
            spaceServiceProxy.spaceFilterPublisher = spaceFilterSubject.asCurrentValuePublisher()
            clientProxy.spaceService = spaceServiceProxy
        }
        
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        if let securityStatePublisher {
            userSession.sessionSecurityStatePublisher = securityStatePublisher
        }
        
        notificationManager = NotificationManagerMock()
        
        agentTaskIndexService = AgentTaskIndexServiceMock(.init(tasks: tasks))
        agentProjectIndexService = AgentProjectIndexServiceMock(.init(projects: projects, pendingChoices: pendingChoices))
        
        viewModel = HomeScreenViewModel(userSession: userSession,
                                        selectedRoomPublisher: CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher(),
                                        appSettings: appSettings,
                                        analyticsService: AnalyticsServiceMock(.init()),
                                        notificationManager: notificationManager,
                                        userIndicatorController: UserIndicatorControllerMock(),
                                        agentTaskIndexService: agentTaskIndexService,
                                        agentProjectIndexService: agentProjectIndexService)
    }
    
    private static var levelZeroSpaceFilters: [SpaceServiceFilter] {
        [SpaceServiceRoom].mockJoinedSpaces.map { SpaceServiceFilter(room: $0, level: 0, descendants: []) }
    }
}

@MainActor
private extension [HomeScreenRoom] {
    var invites: [HomeScreenRoom] {
        filter { room in
            if case .invite = room.type {
                true
            } else {
                false
            }
        }
    }
}

@MainActor
extension HomeScreenViewModelAction: @MainActor @retroactive Equatable {
    public static func == (lhs: HomeScreenViewModelAction, rhs: HomeScreenViewModelAction) -> Bool {
        switch (lhs, rhs) {
        case (.presentRoom(let lhsID), .presentRoom(let rhsID)):
            lhsID == rhsID
        case (.presentRoomDetails(let lhsID), .presentRoomDetails(let rhsID)):
            lhsID == rhsID
        case (.presentReportRoom(let lhsID), .presentReportRoom(let rhsID)):
            lhsID == rhsID
        case (.presentDeclineAndBlock(let lhsUserID, let lhsRoomID), .presentDeclineAndBlock(let rhsUserID, let rhsRoomID)):
            lhsUserID == rhsUserID && lhsRoomID == rhsRoomID
        case (.presentSpace(let lhsSpaceRoomListProxy), .presentSpace(let rhsSpaceRoomListProxy)):
            lhsSpaceRoomListProxy.id == rhsSpaceRoomListProxy.id
        case (.roomLeft(let lhsID), .roomLeft(let rhsID)):
            lhsID == rhsID
        case (.transferOwnership(let lhsID), .transferOwnership(let rhsID)):
            lhsID == rhsID
        case (.presentSecureBackupSettings, .presentSecureBackupSettings):
            true
        case (.presentRecoveryKeyScreen, .presentRecoveryKeyScreen):
            true
        case (.presentEncryptionResetScreen, .presentEncryptionResetScreen):
            true
        case (.presentSettingsScreen, .presentSettingsScreen):
            true
        case (.presentFeedbackScreen, .presentFeedbackScreen):
            true
        case (.presentStartChatScreen, .presentStartChatScreen):
            true
        case (.logout, .logout):
            true
        default:
            false
        }
    }
}

struct SortSpaceFiltersTests {
    private static var filters: [SpaceServiceFilter] {
        [SpaceServiceRoom].mockJoinedSpaces.prefix(4).map { SpaceServiceFilter(room: $0, level: 0, descendants: []) }
    }
    
    @Test
    func emptyOrderKeepsSDKOrder() {
        let sorted = sortSpaceFilters(Self.filters, byOrder: [])
        #expect(sorted.map(\.room.id) == ["space1", "space2", "space3", "space4"])
    }
    
    @Test
    func persistedOrderWins() {
        let sorted = sortSpaceFilters(Self.filters, byOrder: ["space3", "space1"])
        #expect(sorted.map(\.room.id) == ["space3", "space1", "space2", "space4"])
    }
    
    @Test
    func unknownIDsAreAppendedInSDKOrder() {
        // "space9" isn't among the filters at all — it should simply have no effect.
        let sorted = sortSpaceFilters(Self.filters, byOrder: ["space9", "space4"])
        #expect(sorted.map(\.room.id) == ["space4", "space1", "space2", "space3"])
    }
    
    @Test
    func fullyOrderedListMatchesExactly() {
        let sorted = sortSpaceFilters(Self.filters, byOrder: ["space4", "space3", "space2", "space1"])
        #expect(sorted.map(\.room.id) == ["space4", "space3", "space2", "space1"])
    }
}
