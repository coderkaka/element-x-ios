//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import UIKit

enum HomeScreenViewModelAction {
    case presentRoom(roomIdentifier: String)
    case detachRoom(roomIdentifier: String)
    case presentRoomDetails(roomIdentifier: String)
    case presentReportRoom(roomIdentifier: String)
    case presentDeclineAndBlock(userID: String, roomID: String)
    case presentSpace(SpaceRoomListProxyProtocol)
    case roomLeft(roomIdentifier: String)
    case transferOwnership(roomIdentifier: String)
    case presentSecureBackupSettings
    case presentRecoveryKeyScreen
    case presentEncryptionResetScreen
    case presentSettingsScreen
    case presentSpaceManagement
    case presentFeedbackScreen
    case presentStartChatScreen
    case logout
}

enum HomeScreenViewAction {
    case selectRoom(roomIdentifier: String)
    case detachRoom(roomIdentifier: String)
    case showRoomDetails(roomIdentifier: String)
    case leaveRoom(roomIdentifier: String)
    case confirmLeaveRoom(roomIdentifier: String)
    case reportRoom(roomIdentifier: String)
    case showSettings
    case startChat
    case setupRecovery
    case confirmRecoveryKey
    case resetEncryption
    case skipRecoveryKeyConfirmation
    case dismissNewSoundBanner
    case updateVisibleItemRange(Range<Int>)
    case manageSpaces
    case markRoomAsUnread(roomIdentifier: String)
    case markRoomAsRead(roomIdentifier: String)
    case markRoomAsFavourite(roomIdentifier: String, isFavourite: Bool)
    
    case acceptInvite(roomIdentifier: String)
    case declineInvite(roomIdentifier: String)
    
    case selectSpaceFilter(SpaceServiceFilter?)
    /// Opens the 道 picker panel (`ChatsSpaceFiltersScreen`) — sent by both the toolbar button
    /// and the tappable navigation title (fix-spacebar3 contract A/A0).
    case spaceFilters
    
    case tappedPendingChoicesStrip
    case selectPendingChoice(roomID: String)
}

/// The direction a 道 chip is nudged by the "左移"/"右移" context menu actions.
enum MoveDirection {
    case left
    case right
}

enum HomeScreenRoomListMode: CustomStringConvertible {
    case skeletons
    case empty
    case rooms
    
    var description: String {
        switch self {
        case .skeletons:
            return "Showing placeholders"
        case .empty:
            return "Showing empty state"
        case .rooms:
            return "Showing rooms"
        }
    }
}

enum HomeScreenSecurityBannerMode: Equatable {
    case none
    case dismissed
    case show(HomeScreenRecoveryKeyConfirmationBanner.State)
    
    var isDismissed: Bool {
        switch self {
        case .dismissed: true
        default: false
        }
    }
    
    var isShown: Bool {
        switch self {
        case .show: true
        default: false
        }
    }
}

struct HomeScreenViewState: BindableState {
    let userID: String
    var userDisplayName: String?
    var userAvatarURL: URL?
    
    var securityBannerMode = HomeScreenSecurityBannerMode.none
    var shouldShowNewSoundBanner = false
    
    var requiresExtraAccountSetup = false
    
    var rooms: [HomeScreenRoom] = []
    var roomListMode: HomeScreenRoomListMode = .skeletons
    
    var hasPendingInvitations = false
    
    var selectedRoomID: String?
    
    var hideInviteAvatars = false
    
    var roomListActivityVisibility: RoomListActivityVisibility = .current
    
    var reportRoomEnabled = false
    
    var shouldShowSpaceFilters = false
    var availableSpaceFilters: [SpaceServiceFilter] = []
    var selectedSpaceFilter: SpaceServiceFilter?
    /// Whether the user has an unseen invite to a 道 (Space) not in `availableSpaceFilters`
    /// (the SDK's space graph only surfaces joined spaces) — badges the space picker button.
    var hasPendingSpaceInvites = false
    
    /// Current 御案体/通俗版 vocabulary — see `AppTerminology`.
    var terminology = AppTerminology(scenario: .imperial)
    
    var topLevelSpaceFilters: [SpaceServiceFilter] {
        availableSpaceFilters.filter { $0.level == 0 }
    }
    
    /// The navigation title: the selected 道's name when filtering, otherwise 政事堂/工作台
    /// (fix-spacebar3 contract A0 — restores the upstream behaviour of the title tracking the
    /// space filter, on top of the terminology skin).
    var navigationTitle: String {
        selectedSpaceFilter?.room.name ?? terminology.homeTitle
    }
    
    /// Inline room list search is disabled when the dedicated global search tab is shown instead (see `UserSessionFlowCoordinator`).
    var isRoomListSearchEnabled = true
    
    var visibleRooms: [HomeScreenRoom] {
        if roomListMode == .skeletons {
            return placeholderRooms
        }
        
        return rooms
    }
    
    var bindings: HomeScreenViewStateBindings
    
    var placeholderRooms: [HomeScreenRoom] {
        (1...10).map { _ in
            HomeScreenRoom.placeholder()
        }
    }
    
    /// Used to hide all the rooms when the search field is focused and the query is empty
    var shouldHideRoomList: Bool {
        bindings.isSearchFieldFocused && bindings.searchQuery.isEmpty
    }
    
    var shouldShowEmptyFilterState: Bool {
        !bindings.isSearchFieldFocused &&
            (bindings.filtersState.isFiltering || selectedSpaceFilter != nil) &&
            visibleRooms.isEmpty
    }
    
    var shouldShowBanner: Bool {
        securityBannerMode.isShown || shouldShowNewSoundBanner
    }
    
    /// Outstanding `AgentPendingChoiceSummary` items across every room, 道-filtered when a space is selected.
    var pendingChoices: [HomeScreenPendingChoice] = []
}

/// Orders `filters` by their room ID's index in `order`. IDs not listed in `order` keep the SDK's
/// own relative order and are placed after every filter that *is* listed (stable sort throughout).
func sortSpaceFilters(_ filters: [SpaceServiceFilter], byOrder order: [String]) -> [SpaceServiceFilter] {
    guard !order.isEmpty else { return filters }
    
    let indexByRoomID = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    return filters.enumerated()
        .sorted { lhs, rhs in
            let lhsIndex = indexByRoomID[lhs.element.room.id]
            let rhsIndex = indexByRoomID[rhs.element.room.id]
            switch (lhsIndex, rhsIndex) {
            case let (lhsIndex?, rhsIndex?):
                return lhsIndex < rhsIndex
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }
        .map(\.element)
}

/// Like `sortSpaceFilters`, but for a tree-flattened list (each level-0 entry immediately
/// followed by its own level>0 descendants). Reorders only the level-0 entries by `order`,
/// carrying each one's descendant rows along with it so the hierarchy stays intact — used by
/// the 道 picker panel (`ChatsSpaceFiltersScreen`), which unlike the retired chip bar also
/// shows nested/descendant spaces (fix-spacebar3 contract C).
func sortSpaceFilterTree(_ filters: [SpaceServiceFilter], byOrder order: [String]) -> [SpaceServiceFilter] {
    guard !order.isEmpty else { return filters }
    
    var segments: [[SpaceServiceFilter]] = []
    for filter in filters {
        if filter.level == 0 || segments.isEmpty {
            segments.append([filter])
        } else {
            segments[segments.count - 1].append(filter)
        }
    }
    
    let headers = segments.map { $0[0] }
    let orderedHeaders = sortSpaceFilters(headers, byOrder: order)
    let segmentsByHeaderID = Dictionary(zip(headers.map(\.id), segments), uniquingKeysWith: { first, _ in first })
    return orderedHeaders.flatMap { segmentsByHeaderID[$0.id] ?? [$0] }
}

/// Whether `rooms` (typically an always-unfiltered list, e.g. `staticRoomSummaryProvider`)
/// contains an unseen invite to a 道 (Space). The SDK's space graph only surfaces joined spaces,
/// so an invited 道 never gets its own chip — this badges the space picker button instead so the
/// invite stays visible. Shared between 政事堂 and 差事, each tab computing it from its own
/// `staticRoomSummaryProvider`/`seenInvites` copy.
func hasPendingSpaceInvite(in rooms: [RoomSummary], seenInvites: Set<String>) -> Bool {
    rooms.contains { $0.isSpace && $0.joinRequestType?.isInvite == true && !seenInvites.contains($0.id) }
}

/// A single 请旨待批 item shown in the cross-room pending choices strip/sheet.
struct HomeScreenPendingChoice: Identifiable, Equatable {
    let roomID: String
    let eventID: String
    let question: String?
    let roomName: String?
    
    var id: String {
        "\(roomID)|\(eventID)"
    }
}

struct HomeScreenViewStateBindings {
    var filtersState: RoomListFiltersState
    var searchQuery = ""
    var isSearchFieldFocused = false
    
    var alertInfo: AlertInfo<UUID>?
    var leaveRoomAlertItem: LeaveRoomAlertItem?
    
    var isPresentingPendingChoices = false
    
    /// Drives the 道 picker sheet (fix-spacebar3 contract A) — non-nil while it's presented.
    var spaceFiltersViewModel: ChatsSpaceFiltersScreenViewModel?
}

enum CallBadgeType {
    case voice, video, none
}

struct HomeScreenRoom: Identifiable, Equatable {
    enum RoomType: Equatable {
        case placeholder
        case room
        case invite(inviterDetails: RoomInviterDetails?)
        case knock
    }
    
    static let placeholderLastMessage = AttributedString("Hidden last message")
    
    /// The list item identifier is it's room identifier.
    let id: String
    
    /// The real room identifier this item points to
    let roomID: String?
    
    let type: RoomType
    
    var inviter: RoomInviterDetails? {
        if case .invite(let inviter) = type {
            return inviter
        }
        return nil
    }
    
    /// A room/DM invite awaiting the user's accept/decline — used to sort invites to the very
    /// front of the room list (fix-spacebar3 contract B2), ahead of 待批/在办.
    var isInvite: Bool {
        if case .invite = type {
            true
        } else {
            false
        }
    }
    
    let badges: Badges
    struct Badges: Equatable {
        let isDotShown: Bool
        let isMentionShown: Bool
        let isMuteShown: Bool
        let callBadgeType: CallBadgeType
    }
    
    var hasUnreads = false
    
    let name: String
    
    let isDirect: Bool
    
    let isHighlighted: Bool
    
    let isFavourite: Bool
    
    let timestamp: String?
    
    let lastMessage: AttributedString?
    
    enum LastMessageState { case sending, failed }
    let lastMessageState: LastMessageState?
    
    let avatar: RoomAvatar
    
    let canonicalAlias: String?
    
    let isTombstoned: Bool
    
    /// Whether an `io.element.agent.goal` state event marks this room as an agent project (政事案).
    var isProject = false
    /// Unresolved `AgentTaskSummary` count for this room.
    var activeTaskCount = 0
    /// Resolved `AgentTaskSummary` count for this room.
    var doneTaskCount = 0
    /// Outstanding `AgentPendingChoiceSummary` count for this room (待批).
    var pendingChoiceCount = 0
    /// Titles of this room's `active` 标的(`AgentObjectiveSummary`), if any. Empty for rooms
    /// with no objectives (old-protocol rooms, or ones that haven't set one up yet) — the card
    /// falls back to plain 差事 progress in that case.
    var activeObjectiveTitles: [String] = []
    
    var totalTaskCount: Int {
        activeTaskCount + doneTaskCount
    }
    
    var displayedLastMessage: AttributedString? {
        if isTombstoned {
            AttributedString(L10n.screenRoomlistTombstonedRoomDescription)
        } else if lastMessageState == .failed {
            AttributedString(L10n.commonMessageFailedToSend)
        } else {
            lastMessage
        }
    }
    
    static func placeholder() -> HomeScreenRoom {
        HomeScreenRoom(id: UUID().uuidString,
                       roomID: nil,
                       type: .placeholder,
                       badges: .init(isDotShown: false, isMentionShown: false, isMuteShown: false, callBadgeType: .none),
                       name: "Placeholder room name",
                       isDirect: false,
                       isHighlighted: false,
                       isFavourite: false,
                       timestamp: "Now",
                       lastMessage: placeholderLastMessage,
                       lastMessageState: nil,
                       avatar: .room(id: "", name: "", avatarURL: nil),
                       canonicalAlias: nil,
                       isTombstoned: false)
    }
}

extension HomeScreenRoom {
    init(summary: RoomSummary,
         roomListActivityVisibility: RoomListActivityVisibility = .current,
         seenInvites: Set<String> = []) {
        let roomID = summary.id
        
        let isUnseenInvite = summary.joinRequestType?.isInvite == true && !seenInvites.contains(roomID)
        
        let isDotShown = switch roomListActivityVisibility {
        case .current:
            summary.hasUnreadMessages || summary.hasUnreadMentions || summary.hasUnreadNotifications || summary.isMarkedUnread || isUnseenInvite
        case .hide, .show:
            (!summary.isMuted && (summary.hasUnreadNotifications || summary.hasUnreadMentions)) || summary.isMarkedUnread || isUnseenInvite
        }
        
        let isMentionShown = summary.hasUnreadMentions && !summary.isMuted
        let isMuteShown = summary.isMuted
        let isHighlighted = summary.isMarkedUnread || (!summary.isMuted && (summary.hasUnreadNotifications || summary.hasUnreadMentions)) || isUnseenInvite
        
        let callBadge = if summary.hasOngoingCall {
            summary.activeCallIntent == .audio ? CallBadgeType.voice : CallBadgeType.video
        } else {
            CallBadgeType.none
        }
        
        let type: HomeScreenRoom.RoomType = switch summary.joinRequestType {
        case .invite(let inviter): .invite(inviterDetails: inviter.map(RoomInviterDetails.init))
        case .knock: .knock
        case .none: .room
        }
        
        self.init(id: roomID,
                  roomID: summary.id,
                  type: type,
                  badges: .init(isDotShown: isDotShown,
                                isMentionShown: isMentionShown,
                                isMuteShown: isMuteShown,
                                callBadgeType: callBadge),
                  hasUnreads: summary.hasUnreadMessages,
                  name: summary.name,
                  isDirect: summary.isDirect,
                  isHighlighted: isHighlighted,
                  isFavourite: summary.isFavourite,
                  timestamp: summary.lastMessageDate?.formattedMinimal(),
                  lastMessage: summary.lastMessage,
                  lastMessageState: summary.homeScreenLastMessageState,
                  avatar: summary.avatar,
                  canonicalAlias: summary.canonicalAlias,
                  isTombstoned: summary.isTombstoned)
    }
}

private extension RoomSummary {
    var homeScreenLastMessageState: HomeScreenRoom.LastMessageState? {
        if isTombstoned {
            nil
        } else {
            switch lastMessageState {
            case .sending: .sending
            case .failed: .failed
            case .none: .none
            }
        }
    }
}
