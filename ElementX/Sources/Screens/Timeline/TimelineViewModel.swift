//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Algorithms
import Combine
import MatrixRustSDK
import OrderedCollections
import SwiftUI

typealias TimelineViewModelType = StateStoreViewModel<TimelineViewState, TimelineViewAction>

class TimelineViewModel: TimelineViewModelType, TimelineViewModelProtocol {
    private enum Constants {
        static let paginationEventLimit: UInt16 = 20
        static let detachedTimelineSize: UInt16 = 100
        static let focusTimelineToastIndicatorID = "RoomScreenFocusTimelineToastIndicator"
        static let toastErrorID = "RoomScreenToastError"
    }
    
    private let roomProxy: JoinedRoomProxyProtocol
    private let timelineController: TimelineControllerProtocol
    private let userSession: UserSessionProtocol
    private let mediaPlayerProvider: MediaPlayerProviderProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let appMediator: AppMediatorProtocol
    private let appSettings: AppSettings
    private let analyticsService: AnalyticsServiceProtocol
    private let emojiProvider: EmojiProviderProtocol
    private let timelineControllerFactory: TimelineControllerFactoryProtocol
    
    private let timelineInteractionHandler: TimelineInteractionHandler
    
    private let composerFocusedSubject = PassthroughSubject<Bool, Never>()
    
    private let actionsSubject: PassthroughSubject<TimelineViewModelAction, Never> = .init()
    var actions: AnyPublisher<TimelineViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private let roomTaskSummarySubject = CurrentValueSubject<RoomTaskSummary, Never>(.init())
    var roomTaskSummaryPublisher: CurrentValuePublisher<RoomTaskSummary, Never> {
        roomTaskSummarySubject.asCurrentValuePublisher()
    }
    
    /// The authoritative, state-enumerated view of the room's agent tasks (`eventID` empty until
    /// enriched against currently-loaded timeline items in `updateRoomTaskSummary`). Refreshed by
    /// `refreshStateEnumeratedTaskSummary` and merged into `roomTaskSummary` on every rebuild.
    private var stateEnumeratedTasks = [RoomTaskSummary.Task]()
    /// Every `io.element.agent.choice_request` state event the room currently has, pending or not —
    /// kept unfiltered so a resolution can override a timeline guess that's still pending.
    private var stateEnumeratedChoiceEvents = [AgentChoiceStateIndexEvent]()
    
    private var currentUserProxy: RoomMemberProxyProtocol?
    
    private var paginateBackwardsTask: Task<Void, Never>?
    private var paginateForwardsTask: Task<Void, Never>?
    
    init(roomProxy: JoinedRoomProxyProtocol,
         focussedEventID: String? = nil,
         timelineController: TimelineControllerProtocol,
         userSession: UserSessionProtocol,
         mediaPlayerProvider: MediaPlayerProviderProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         appMediator: AppMediatorProtocol,
         appSettings: AppSettings,
         analyticsService: AnalyticsServiceProtocol,
         emojiProvider: EmojiProviderProtocol,
         linkMetadataProvider: LinkMetadataProviderProtocol,
         timelineControllerFactory: TimelineControllerFactoryProtocol) {
        self.roomProxy = roomProxy
        self.timelineController = timelineController
        self.userSession = userSession
        self.mediaPlayerProvider = mediaPlayerProvider
        self.appSettings = appSettings
        self.analyticsService = analyticsService
        self.userIndicatorController = userIndicatorController
        self.appMediator = appMediator
        self.emojiProvider = emojiProvider
        self.timelineControllerFactory = timelineControllerFactory
        
        let voiceMessageRecorder = VoiceMessageRecorder(audioRecorder: AudioRecorder(), mediaPlayerProvider: mediaPlayerProvider)
        
        timelineInteractionHandler = TimelineInteractionHandler(roomProxy: roomProxy,
                                                                timelineController: timelineController,
                                                                userSession: userSession,
                                                                mediaPlayerProvider: mediaPlayerProvider,
                                                                voiceMessageRecorder: voiceMessageRecorder,
                                                                userIndicatorController: userIndicatorController,
                                                                appMediator: appMediator,
                                                                appSettings: appSettings,
                                                                analyticsService: analyticsService,
                                                                emojiProvider: emojiProvider,
                                                                linkMetadataProvider: linkMetadataProvider,
                                                                timelineControllerFactory: timelineControllerFactory)
        
        let hideTimelineMedia = switch userSession.clientProxy.timelineMediaVisibilityPublisher.value {
        case .always:
            false
        case .privateOnly:
            !(roomProxy.infoPublisher.value.isPrivate ?? true)
        case .never:
            true
        }
        super.init(initialViewState: TimelineViewState(timelineKind: timelineController.timelineKind,
                                                       roomID: roomProxy.id,
                                                       isDM: roomProxy.infoPublisher.value.isDM,
                                                       timelineState: TimelineState(focussedEvent: focussedEventID.map { .init(eventID: $0, appearance: .immediate) }),
                                                       ownUserID: roomProxy.ownUserID,
                                                       hideTimelineMedia: hideTimelineMedia,
                                                       isViewSourceEnabled: appSettings.viewSourceEnabled,
                                                       areThreadsEnabled: appSettings.threadsEnabled,
                                                       linkPreviewsEnabled: appSettings.linkPreviewsEnabled,
                                                       jumpToReadMarkerEnabled: appSettings.jumpToReadMarkerEnabled,
                                                       hasPredecessor: roomProxy.predecessorRoom != nil,
                                                       pinnedEventIDs: roomProxy.infoPublisher.value.pinnedEventIDs,
                                                       emojiProvider: emojiProvider,
                                                       linkMetadataProvider: hideTimelineMedia ? nil : linkMetadataProvider,
                                                       mapTilerSettings: appSettings.mapTilerSettings.publisher.value,
                                                       bindings: .init(reactionsCollapsed: [:])),
                   mediaProvider: userSession.mediaProvider)
        
        if focussedEventID != nil {
            // The timeline controller will start loading a detached timeline.
            showFocusLoadingIndicator()
        }
        
        setupSubscriptions()
        setupDirectRoomSubscriptionsIfNeeded()
        
        state.audioPlayerStateProvider = { [weak self] itemID -> AudioPlayerState? in
            guard let self else {
                return nil
            }
            
            return self.timelineInteractionHandler.audioPlayerState(for: itemID)
        }
        
        state.pillContextUpdater = { [weak self] pillContext in
            self?.pillContextUpdater(pillContext)
        }
        
        state.roomNameForIDResolver = { [weak self] roomID in
            self?.userSession.clientProxy.roomSummaryForIdentifier(roomID)?.name
        }
        
        state.roomNameForAliasResolver = { [weak self] alias in
            self?.userSession.clientProxy.roomSummaryForAlias(alias)?.name
        }
        
        state.timelineState.paginationState = timelineController.paginationState
        buildTimelineViews(timelineItems: timelineController.timelineItems)
        // Room state is the authoritative task/choice source and already holds updates the
        // timeline hasn't paginated in yet — enumerate it once up front so the chip is right
        // immediately on room entry, instead of waiting for the first timeline diff.
        refreshStateEnumeratedTaskSummary()
        
        updateRoomInfo(roomProxy.infoPublisher.value)
        updateMembers(roomProxy.membersPublisher.value)
        
        // Note: beware if we get to e.g. restore a reply / edit,
        // maybe we are tracking a non-needed first initial state
        trackComposerMode(.default)
    }
    
    // MARK: - Public
    
    override func process(viewAction: TimelineViewAction) {
        switch viewAction {
        case .itemAppeared(let id):
            Task { await timelineController.processItemAppearance(id) }
        case .itemDisappeared(let id):
            Task { await timelineController.processItemDisappearance(id) }
        case .mediaTapped(let id):
            Task { await handleMediaTapped(with: id) }
        case .itemSendInfoTapped(let itemID):
            handleItemSendInfoTapped(itemID: itemID)
        case .toggleReaction(let emoji, let itemID):
            emojiProvider.markEmojiAsFrequentlyUsed(emoji)
            
            guard case let .event(_, eventOrTransactionID) = itemID else {
                fatalError()
            }
            
            Task { await timelineController.toggleReaction(emoji, to: eventOrTransactionID) }
        case .sendReadReceiptIfNeeded(let lastVisibleItemID):
            Task { await sendReadReceiptIfNeeded(for: lastVisibleItemID) }
        case .paginateBackwards:
            paginateBackwards()
        case .paginateForwards:
            paginateForwards()
        case .scrollToBottom:
            scrollToBottom()
        case .scrollToFirstItemForCurrentDate:
            state.timelineState.scrollToFirstItemForDatePublisher.send()
        case .scrollToReadMarker:
            Task { await scrollToReadMarker() }
        case .markAllAsRead:
            state.bindings.hasNewMessagesAtBottom = false
            Task {
                _ = await roomProxy.markAsRead(receiptType: .fullyRead)
                // Clear locally so the jump-to-unread button hides without waiting
                // for the SDK to push a refreshed RoomInfo. Doing this after the
                // await means any stale RoomInfo update racing the mark-as-read
                // call has already landed and can't overwrite this clear.
                state.timelineState.fullyReadEventID = nil
            }
        case .displayTimelineItemMenu(let itemID):
            timelineInteractionHandler.displayTimelineItemActionMenu(for: itemID)
        case .handleTimelineItemMenuAction(let itemID, let action):
            timelineInteractionHandler.handleTimelineItemMenuAction(action, itemID: itemID)
        case .tappedOnSenderDetails(let sender):
            handleTappedOnSenderDetails(sender: sender)
        case .displayEmojiPicker(let itemID):
            timelineInteractionHandler.displayEmojiPicker(for: itemID)
        case .displayReactionSummary(let itemID, let key):
            displayReactionSummary(for: itemID, selectedKey: key)
        case .displayReadReceipts(let itemID):
            displayReadReceipts(for: itemID)
        case .displayThread(let itemID):
            actionsSubject.send(.displayThread(itemID: itemID))
        case .tappedRoomTaskChip:
            // Smart shortcut (决策 6): exactly one active task and nothing else goes straight
            // to its detail; any other non-empty summary opens the task panel.
            let summary = state.roomTaskSummary
            if let task = summary.activeTasks.first, summary.activeTasks.count == 1, summary.pendingChoices.isEmpty, summary.doneTasks.isEmpty {
                actionsSubject.send(.presentCanvasSteps(eventID: task.eventID, taskID: task.taskID))
            } else if !summary.isEmpty {
                actionsSubject.send(.presentTaskPanel)
            }
        case .tappedAgentTaskCard(let itemID, let taskID):
            // Prefer the state-resolved task from the summary (current data, matched by taskID
            // since state-only tasks carry no event ID); fall back to the tapped card's own event
            // ID so the flow coordinator can still push a detail built from the message snapshot.
            let summary = state.roomTaskSummary
            if let task = (summary.activeTasks + summary.doneTasks).first(where: { $0.taskID == taskID }) {
                actionsSubject.send(.presentCanvasSteps(eventID: task.eventID, taskID: task.taskID))
            } else if let eventID = itemID.eventID {
                actionsSubject.send(.presentCanvasSteps(eventID: eventID, taskID: taskID))
            }
        case .fetchStateEvent(let eventType, let stateKey):
            fetchStateEvent(eventType: eventType, stateKey: stateKey)
        case .handlePasteOrDrop(let providers):
            timelineInteractionHandler.handlePasteOrDrop(providers)
        case .handlePollAction(let pollAction):
            handlePollAction(pollAction)
        case .handleChoiceRequestAction(let choiceRequestAction):
            handleChoiceRequestAction(choiceRequestAction)
        case .handleAudioPlayerAction(let audioPlayerAction):
            handleAudioPlayerAction(audioPlayerAction)
        case .stopLiveLocationSharing(let id):
            state.stoppedLiveLocationIDs.insert(id)
            Task { await stopLiveLocationSharing() }
        case .focusOnEventID(let eventID):
            Task { await focusOnEvent(eventID: eventID) }
        case .focusLive:
            focusLive()
        case .scrolledToFocussedItem:
            didScrollToFocussedItem()
        case .hasSwitchedTimeline:
            Task { state.timelineState.isSwitchingTimelines = false }
        case let .hasScrolled(direction):
            actionsSubject.send(.hasScrolled(direction: direction))
        case .displayPredecessorRoom:
            guard let predecessorID = roomProxy.predecessorRoom?.roomId else {
                fatalError("Predecessor room should exist if this action is triggered.")
            }
            let serverNames = roomProxy.knownServerNames(maxCount: 50) // Limit to the same number used by ClientProxy.resolveRoomAlias(_:)
            actionsSubject.send(.displayRoom(roomID: predecessorID, via: Array(serverNames)))
        }
    }
    
    func process(composerAction: ComposerToolbarViewModelAction) {
        switch composerAction {
        case .sendMessage(let message, let html, let mode, let intentionalMentions):
            Task {
                await sendCurrentMessage(message,
                                         html: html,
                                         mode: mode,
                                         intentionalMentions: intentionalMentions)
            }
        case .editLastMessage:
            editLastMessage()
        case .attach(let attachment):
            attach(attachment)
        case .handlePasteOrDrop(let providers):
            timelineInteractionHandler.handlePasteOrDrop(providers)
        case .composerModeChanged(mode: let mode):
            trackComposerMode(mode)
        case .composerFocusedChanged(isFocused: let isFocused):
            composerFocusedSubject.send(isFocused)
        case .voiceMessage(let voiceMessageAction):
            processVoiceMessageAction(voiceMessageAction)
        case .contentChanged(let isEmpty):
            guard appSettings.sharePresence else {
                return
            }
            
            Task {
                await roomProxy.sendTypingNotification(isTyping: !isEmpty)
            }
        }
    }
    
    func focusOnEvent(eventID: String) async {
        if state.timelineState.hasLoadedItem(with: eventID) {
            state.timelineState.focussedEvent = .init(eventID: eventID, appearance: .animated)
            return
        }
        
        showFocusLoadingIndicator()
        defer {
            hideFocusLoadingIndicator()
        }
        
        switch await timelineController.focusOnEvent(eventID, timelineSize: Constants.detachedTimelineSize) {
        case .success:
            state.timelineState.focussedEvent = .init(eventID: eventID, appearance: .immediate)
        case .failure(let error):
            MXLog.error("Failed to focus on event \(eventID)")
            
            if case .eventNotFound = error {
                displayErrorToast(L10n.errorMessageNotFound)
            } else {
                displayErrorToast(L10n.commonFailed)
            }
        }
    }
    
    func stopLiveLocationSharing() async {
        await userSession.liveLocationManager.stopLiveLocation(roomID: roomProxy.id)
    }
    
    func makeForwardingItem(for itemID: TimelineItemIdentifier) async -> MessageForwardingItem? {
        guard let content = await timelineController.messageEventContent(for: itemID) else { return nil }
        return .init(id: itemID, roomID: roomProxy.id, content: content)
    }
    
    // MARK: - Private
    
    private func handleTappedOnSenderDetails(sender: TimelineItemSender) {
        let memberDetails: ManageRoomMemberDetails = if let memberProxy = roomProxy.membersPublisher.value.first(where: { $0.userID == sender.id }) {
            .memberDetails(roomMember: .init(withProxy: memberProxy))
        } else {
            .loadingMemberDetails(sender: sender)
        }
        
        let viewModel = ManageRoomMemberSheetViewModel(memberDetails: memberDetails,
                                                       permissions: .init(canKick: state.canCurrentUserKick,
                                                                          canBan: state.canCurrentUserBan,
                                                                          ownPowerLevel: currentUserProxy?.powerLevel ?? .init(value: 0)),
                                                       roomProxy: roomProxy,
                                                       userIndicatorController: userIndicatorController,
                                                       analyticsService: analyticsService,
                                                       mediaProvider: userSession.mediaProvider)
        
        viewModel.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .dismiss(let shouldShowDetails):
                state.bindings.manageMemberViewModel = nil
                if shouldShowDetails {
                    actionsSubject.send(.displaySenderDetails(userID: sender.id))
                }
            }
        }
        .store(in: &cancellables)
        state.bindings.manageMemberViewModel = viewModel
    }
    
    private func focusLive() {
        timelineController.focusLive()
    }
    
    private func didScrollToFocussedItem() {
        if var focussedEvent = state.timelineState.focussedEvent {
            focussedEvent.appearance = .hasAppeared
            state.timelineState.focussedEvent = focussedEvent
            hideFocusLoadingIndicator()
            analyticsService.signpost.finishTransaction(.notificationToMessage)
        }
    }
    
    private func editLastMessage() {
        guard let item = timelineController.timelineItems.reversed().first(where: {
            guard let item = $0 as? EventBasedMessageTimelineItemProtocol else {
                return false
            }
            
            return item.sender.id == roomProxy.ownUserID && item.isEditable
        }) else {
            return
        }
        
        timelineInteractionHandler.handleTimelineItemMenuAction(.edit, itemID: item.id)
    }
    
    private func attach(_ attachment: ComposerAttachmentType) {
        switch attachment {
        case .camera:
            actionsSubject.send(.displayCameraPicker)
        case .photoLibrary:
            actionsSubject.send(.displayMediaPicker)
        case .file:
            actionsSubject.send(.displayDocumentPicker)
        case .location:
            actionsSubject.send(.displayLocationPicker)
        case .poll:
            actionsSubject.send(.displayNewPollForm)
        }
    }
    
    private func handlePollAction(_ action: TimelineViewPollAction) {
        switch action {
        case let .sendResponse(pollStartID, answerIDs):
            timelineInteractionHandler.sendPollResponse(pollStartID: pollStartID, answerIDs: answerIDs)
        case let .end(pollStartID):
            displayAlert(.pollEndConfirmation(pollStartID))
        case .edit(let eventID, let poll):
            actionsSubject.send(.displayEditPollForm(eventID: eventID, poll: poll))
        }
    }
    
    private func handleChoiceRequestAction(_ action: TimelineViewChoiceRequestAction) {
        switch action {
        case let .sendResponse(requestEventID, body):
            timelineInteractionHandler.sendChoiceRequestResponse(requestEventID: requestEventID, body: body)
        }
    }
    
    private func handleAudioPlayerAction(_ action: TimelineAudioPlayerAction) {
        switch action {
        case .playPause(let itemID):
            Task { await timelineInteractionHandler.playPauseAudio(for: itemID) }
        case .seek(let itemID, let progress):
            Task { await timelineInteractionHandler.seekAudio(for: itemID, progress: progress) }
        case .changePlaybackSpeed(let itemID):
            timelineInteractionHandler.changePlaybackSpeed(for: itemID)
        }
    }
    
    private func processVoiceMessageAction(_ action: ComposerToolbarVoiceMessageAction) {
        switch action {
        case .startRecording:
            Task {
                await mediaPlayerProvider.detachAllStates(except: nil)
                await timelineInteractionHandler.startRecordingVoiceMessage()
            }
        case .stopRecording:
            Task { await timelineInteractionHandler.stopRecordingVoiceMessage() }
        case .cancelRecording:
            Task { await timelineInteractionHandler.cancelRecordingVoiceMessage() }
        case .deleteRecording:
            Task { await timelineInteractionHandler.deleteCurrentVoiceMessage() }
        case .send:
            Task { await timelineInteractionHandler.sendCurrentVoiceMessage() }
        case .startPlayback:
            Task { await timelineInteractionHandler.startPlayingRecordedVoiceMessage() }
        case .pausePlayback:
            timelineInteractionHandler.pausePlayingRecordedVoiceMessage()
        case .seekPlayback(let progress):
            Task { await timelineInteractionHandler.seekRecordedVoiceMessage(to: progress) }
        case .scrubPlayback(let scrubbing):
            Task { await timelineInteractionHandler.scrubVoiceMessagePlayback(scrubbing: scrubbing) }
        }
    }
    
    private func updateMembers(_ members: [RoomMemberProxyProtocol]) {
        state.members = members.reduce(into: [String: RoomMemberState]()) { dictionary, member in
            dictionary[member.userID] = RoomMemberState(displayName: member.displayName, avatarURL: member.avatarURL)
            if member.userID == roomProxy.ownUserID {
                currentUserProxy = member
            }
        }
    }
    
    private func updateRoomInfo(_ roomInfo: RoomInfoProxyProtocol) {
        state.pinnedEventIDs = roomInfo.pinnedEventIDs
        state.isDM = roomInfo.isDM
        state.timelineState.fullyReadEventID = roomInfo.fullyReadEventID
        
        if let powerLevels = roomInfo.powerLevels {
            state.canCurrentUserSendMessage = powerLevels.canOwnUser(sendMessage: .roomMessage)
            state.canCurrentUserRedactOthers = powerLevels.canOwnUserRedactOther()
            state.canCurrentUserRedactSelf = powerLevels.canOwnUserRedactOwn()
            state.canCurrentUserPin = powerLevels.canOwnUserPinOrUnpin()
            state.canCurrentUserKick = powerLevels.canOwnUserKick()
            state.canCurrentUserBan = powerLevels.canOwnUserBan()
        }
    }
    
    private func setupSubscriptions() {
        timelineController.callbacks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] callback in
                guard let self else { return }
                
                switch callback {
                case .updatedTimelineItems(let updatedItems, let isSwitchingTimelines):
                    buildTimelineViews(timelineItems: updatedItems, isSwitchingTimelines: isSwitchingTimelines)
                    
                    if !updatedItems.isEmpty {
                        analyticsService.signpost.finishTransaction(.openRoom)
                    }
                case .paginationState(let paginationState):
                    if state.timelineState.paginationState != paginationState {
                        state.timelineState.paginationState = paginationState
                    }
                case .isLive(let isLive):
                    if state.timelineState.isLive != isLive {
                        state.timelineState.isLive = isLive
                        
                        // Remove the event highlight *only* when transitioning from non-live to live.
                        if isLive, state.timelineState.focussedEvent != nil {
                            state.timelineState.focussedEvent = nil
                        }
                    }
                case .messageSentOrEdited:
                    actionsSubject.send(.composer(action: .clear))
                }
            }
            .store(in: &cancellables)
        
        roomProxy.infoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomInfo in
                self?.updateRoomInfo(roomInfo)
            }
            .store(in: &cancellables)
        
        // Custom state event types aren't delivered by sliding sync, so agent task state changes
        // can't be observed directly — instead, any room activity re-checks the tracked state events.
        roomProxy.infoPublisher
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshFetchedStateEvents()
                self?.refreshStateEnumeratedTaskSummary()
            }
            .store(in: &cancellables)
        
        setupAppSettingsSubscriptions()
        
        roomProxy.membersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateMembers($0) }
            .store(in: &cancellables)
        
        roomProxy.typingMembersPublisher
            .receive(on: DispatchQueue.main)
            .filter { [weak self] _ in self?.appSettings.sharePresence ?? false }
            .weakAssign(to: \.state.typingMembers, on: self)
            .store(in: &cancellables)
        
        timelineInteractionHandler.actions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .composer(let action):
                    actionsSubject.send(.composer(action: action))
                case .displayAudioRecorderPermissionError:
                    displayAlert(.audioRecodingPermissionError)
                case .displayErrorToast(let title):
                    displayErrorToast(title)
                case .displayEmojiPicker(let itemID, let selectedEmojis):
                    actionsSubject.send(.displayEmojiPicker(itemID: itemID, selectedEmojis: selectedEmojis))
                case .displayMessageForwarding(let itemID):
                    Task { await self.forwardMessage(itemID: itemID) }
                case .displayEditPollForm(let eventID, let poll):
                    actionsSubject.send(.displayEditPollForm(eventID: eventID, poll: poll))
                case .displayReportContent(let itemID, let senderID):
                    actionsSubject.send(.displayReportContent(itemID: itemID, senderID: senderID))
                case .displayMediaUploadPreviewScreen(let mediaURLs):
                    actionsSubject.send(.displayMediaUploadPreviewScreen(mediaURLs: mediaURLs))
                case .showActionMenu(let actionMenuInfo):
                    if case .media(.mediaFilesScreen) = timelineController.timelineKind,
                       let item = actionMenuInfo.item as? EventBasedMessageTimelineItemProtocol {
                        actionsSubject.send(.displayMediaDetails(item: item))
                    } else {
                        self.state.bindings.actionMenuInfo = actionMenuInfo
                    }
                case .showDebugInfo(let debugInfo):
                    state.bindings.debugInfo = debugInfo
                case .viewInRoomTimeline(let eventID):
                    Task { await self.viewInRoomTimeline(eventID: eventID) }
                case .displayThread(let itemID):
                    actionsSubject.send(.displayThread(itemID: itemID))
                case .showTranslation(let text):
                    self.state.bindings.textToBeTranslated = text
                    self.state.bindings.showTranslation = true
                }
            }
            .store(in: &cancellables)
    }
    
    func viewInRoomTimeline(eventID: String) async {
        switch await roomProxy.loadOrFetchEventDetails(for: eventID) {
        case .success(let event):
            let threadRootEventID: String? = if appSettings.threadsEnabled {
                event.threadRootEventId()
            } else {
                nil
            }
            actionsSubject.send(.viewInRoomTimeline(eventID: eventID, threadRootEventID: threadRootEventID))
        case .failure:
            userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
        }
    }
    
    private func setupAppSettingsSubscriptions() {
        appSettings.sharePresencePublisher
            .weakAssign(to: \.state.showReadReceipts, on: self)
            .store(in: &cancellables)
        
        appSettings.viewSourceEnabledPublisher
            .weakAssign(to: \.state.isViewSourceEnabled, on: self)
            .store(in: &cancellables)
        
        appSettings.threadsEnabledPublisher
            .weakAssign(to: \.state.areThreadsEnabled, on: self)
            .store(in: &cancellables)
        
        appSettings.jumpToReadMarkerEnabledPublisher
            .weakAssign(to: \.state.jumpToReadMarkerEnabled, on: self)
            .store(in: &cancellables)
        
        userSession.clientProxy.timelineMediaVisibilityPublisher
            .removeDuplicates()
            .flatMap { [weak self] timelineMediaVisibility -> AnyPublisher<Bool, Never> in
                switch timelineMediaVisibility {
                case .always:
                    return Just(false).eraseToAnyPublisher()
                case .never:
                    return Just(true).eraseToAnyPublisher()
                case .privateOnly:
                    guard let self else { return Just(false).eraseToAnyPublisher() }
                    return roomProxy.infoPublisher
                        .map { !($0.isPrivate ?? false) }
                        .removeDuplicates()
                        .eraseToAnyPublisher()
                }
            }
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.hideTimelineMedia, on: self)
            .store(in: &cancellables)
    }
    
    private func setupDirectRoomSubscriptionsIfNeeded() {
        guard roomProxy.infoPublisher.value.isDirect else {
            return
        }
        
        let shouldShowInviteAlert = composerFocusedSubject
            .removeDuplicates()
            .map { [weak self] isFocused in
                guard let self else { return false }
                
                return isFocused && self.roomProxy.infoPublisher.value.isUserAloneInDirectRoom
            }
            // We want to show the alert just once, so we are taking the first "true" emitted
            .first { $0 }
        
        shouldShowInviteAlert
            .sink { [weak self] _ in
                self?.displayAlert(.inviteAgain)
            }
            .store(in: &cancellables)
    }
    
    private func paginateBackwards() {
        guard paginateBackwardsTask == nil else {
            return
        }
        
        paginateBackwardsTask = Task { [weak self] in
            guard let self else {
                return
            }
            
            switch await timelineController.paginateBackwards(requestSize: Constants.paginationEventLimit) {
            case .failure:
                displayErrorToast(L10n.errorFailedLoadingMessages)
            default:
                break
            }
            paginateBackwardsTask = nil
        }
    }
    
    private func paginateForwards() {
        guard paginateForwardsTask == nil else {
            return
        }
        
        paginateForwardsTask = Task { [weak self] in
            guard let self else {
                return
            }
            
            switch await timelineController.paginateForwards(requestSize: Constants.paginationEventLimit) {
            case .failure:
                displayErrorToast(L10n.errorFailedLoadingMessages)
            default:
                break
            }
            
            if state.timelineState.paginationState.forward == .endReached {
                focusLive()
            }
            
            paginateForwardsTask = nil
        }
    }
    
    private func scrollToBottom() {
        if state.timelineState.isLive {
            state.timelineState.scrollToBottomPublisher.send(())
        } else {
            focusLive()
        }
    }
    
    private func scrollToReadMarker() async {
        // Primary: SDK has materialised the virtual ReadMarker. Smooth in-window scroll.
        if let readMarkerID = state.timelineState.readMarkerUniqueID {
            state.timelineState.scrollToReadMarkerPublisher.send(readMarkerID)
            return
        }
        
        // Fallback: mirror the same-room permalink flow exactly
        // (RoomFlowCoordinator.handleChildEventRoute lines 223-258): pre-fetch the
        // event first to prime the SDK's event cache, then focus on it via the
        // same focusOnEvent path permalinks use.
        guard let fullyReadEventID = state.timelineState.fullyReadEventID else { return }
        
        switch await roomProxy.loadOrFetchEventDetails(for: fullyReadEventID) {
        case .success:
            await focusOnEvent(eventID: fullyReadEventID)
        case .failure:
            displayErrorToast(L10n.errorMessageNotFound)
        }
    }
    
    private func sendReadReceiptIfNeeded(for lastVisibleItemID: TimelineItemIdentifier) async {
        guard appMediator.appState == .active else { return }
        
        await timelineController.sendReadReceipt(for: lastVisibleItemID)
    }
    
    private func handleMediaTapped(with itemID: TimelineItemIdentifier) async {
        state.showLoading = true
        let action = await timelineInteractionHandler.processItemTap(itemID)
        
        switch action {
        case .displayMediaPreview(let item, let timelineViewModelKind):
            actionsSubject.send(.composer(action: .removeFocus)) // Hide the keyboard otherwise a big white space is sometimes shown when dismissing the preview.
            
            let mediaPreviewViewModel = makeMediaPreviewViewModel(item: item, timelineViewModelKind: timelineViewModelKind)
            actionsSubject.send(.displayMediaPreview(mediaPreviewViewModel))
        case .displayLocation(let location):
            actionsSubject.send(.displayLocation(location))
        case .displayLiveLocation(let sender, let initialLiveLocationShare):
            actionsSubject.send(.displayLiveLocation(sender: sender, initialLiveLocationShare: initialLiveLocationShare))
        case .none:
            break
        }
        state.showLoading = false
    }
    
    private func handleItemSendInfoTapped(itemID: TimelineItemIdentifier) {
        guard let timelineItem = timelineController.timelineItems.firstUsingStableID(itemID) else {
            MXLog.warning("Couldn't find timeline item.")
            return
        }
        
        guard let eventTimelineItem = timelineItem as? EventBasedTimelineItemProtocol else {
            fatalError("Only events can have send info.")
        }
        
        if case .sendingFailed(.unknown) = eventTimelineItem.properties.deliveryStatus {
            displayAlert(.sendingFailed)
        } else if case let .sendingFailed(.verifiedUser(failure)) = eventTimelineItem.properties.deliveryStatus {
            guard let sendHandle = timelineController.sendHandle(for: itemID) else {
                MXLog.error("Cannot find send handle for \(itemID).")
                return
            }
            
            actionsSubject.send(.displayResolveSendFailure(failure: failure,
                                                           sendHandle: sendHandle))
            
        } else if let forwarderMessage = eventTimelineItem.properties.encryptionForwarder?.message {
            displayAlert(.encryptionForwarder(forwarderMessage))
        } else if let authenticityMessage = eventTimelineItem.properties.encryptionAuthenticity?.message {
            displayAlert(.encryptionAuthenticity(authenticityMessage))
        }
    }
    
    private func slashCommand(message: String) -> SlashCommand? {
        for command in SlashCommand.allCases where message.starts(with: command.rawValue) {
            return command
        }
        return nil
    }
    
    private func handleJoinCommand(message: String) async {
        guard let alias = String(message.dropFirst(SlashCommand.join.rawValue.count))
            .components(separatedBy: .whitespacesAndNewlines)
            .first,
            case let .success(resolvedAlias) = await userSession.clientProxy.resolveRoomAlias(alias) else {
            return
        }
        
        actionsSubject.send(.displayRoom(roomID: resolvedAlias.roomId, via: resolvedAlias.servers))
    }
    
    private func sendCurrentMessage(_ message: String, html: String?, mode: ComposerMode, intentionalMentions: IntentionalMentions) async {
        guard !message.isEmpty else {
            fatalError("This message should never be empty")
        }
        
        switch mode {
        case .reply(let eventID, _, _):
            await timelineController.sendMessage(message,
                                                 html: html,
                                                 inReplyToEventID: eventID,
                                                 intentionalMentions: intentionalMentions)
        case .edit(let originalEventOrTransactionID, .default):
            await timelineController.edit(originalEventOrTransactionID,
                                          message: message,
                                          html: html,
                                          intentionalMentions: intentionalMentions)
        case .edit(let originalEventOrTransactionID, .addCaption),
             .edit(let originalEventOrTransactionID, .editCaption):
            await timelineController.editCaption(originalEventOrTransactionID,
                                                 message: message,
                                                 html: html,
                                                 intentionalMentions: intentionalMentions)
        case .default:
            switch slashCommand(message: message) {
            case .join:
                await handleJoinCommand(message: message)
            case .none:
                await timelineController.sendMessage(message,
                                                     html: html,
                                                     inReplyToEventID: nil,
                                                     intentionalMentions: intentionalMentions)
            }
        case .recordVoiceMessage, .previewVoiceMessage:
            fatalError("invalid composer mode.")
        }
        
        scrollToBottom()
    }
    
    private func trackComposerMode(_ mode: ComposerMode) {
        var isEdit = false
        var isReply = false
        switch mode {
        case .edit:
            isEdit = true
        case .reply:
            isReply = true
        default:
            break
        }
        
        analyticsService.trackComposer(inThread: false, isEditing: isEdit, isReply: isReply, startsThread: nil)
    }
    
    private func makeMediaPreviewViewModel(item: EventBasedMessageTimelineItemProtocol,
                                           timelineViewModelKind: TimelineControllerAction.TimelineViewModelKind) -> TimelineMediaPreviewViewModel {
        let timelineViewModel = switch timelineViewModelKind {
        case .active: self
        case .new(let newViewModel): newViewModel
        }
        
        return TimelineMediaPreviewViewModel(initialItem: item,
                                             timelineViewModel: timelineViewModel,
                                             mediaProvider: userSession.mediaProvider,
                                             photoLibraryManager: PhotoLibraryManager(),
                                             userIndicatorController: userIndicatorController,
                                             appMediator: appMediator)
    }
    
    // MARK: - Timeline Item Building
    
    private func buildTimelineViews(timelineItems: [RoomTimelineItemProtocol], isSwitchingTimelines: Bool = false) {
        var timelineItemsDictionary = OrderedDictionary<TimelineItemIdentifier.UniqueID, RoomTimelineItemViewState>()
        
        timelineItems.filter { $0 is RedactedRoomTimelineItem }.forEach { timelineItem in
            // Stops the audio player when a voice message is redacted.
            guard let playerState = mediaPlayerProvider.playerState(for: .timelineItemIdentifier(timelineItem.id)) else {
                return
            }
            
            Task { @MainActor in
                playerState.detachAudioPlayer()
                mediaPlayerProvider.unregister(audioPlayerState: playerState)
            }
        }
        
        let itemsGroupedByTimelineDisplayStyle = timelineItems.chunked { current, next in
            canGroupItem(timelineItem: current, with: next)
        }
        
        for itemGroup in itemsGroupedByTimelineDisplayStyle {
            guard !itemGroup.isEmpty else {
                MXLog.error("Found empty item group")
                continue
            }
            
            if itemGroup.count == 1 {
                if let firstItem = itemGroup.first {
                    timelineItemsDictionary.updateValue(updateViewState(item: firstItem, groupStyle: .single),
                                                        forKey: firstItem.id.uniqueID)
                }
            } else {
                for (index, item) in itemGroup.enumerated() {
                    if index == 0 {
                        timelineItemsDictionary.updateValue(updateViewState(item: item, groupStyle: state.timelineKind == .pinned ? .single : .first),
                                                            forKey: item.id.uniqueID)
                    } else if index == itemGroup.count - 1 {
                        timelineItemsDictionary.updateValue(updateViewState(item: item, groupStyle: state.timelineKind == .pinned ? .single : .last),
                                                            forKey: item.id.uniqueID)
                    } else {
                        timelineItemsDictionary.updateValue(updateViewState(item: item, groupStyle: state.timelineKind == .pinned ? .single : .middle),
                                                            forKey: item.id.uniqueID)
                    }
                }
            }
        }
        
        if isSwitchingTimelines {
            state.timelineState.isSwitchingTimelines = true
        }
        
        updateHasNewMessagesAtBottom(with: timelineItemsDictionary)
        
        state.timelineState.itemsDictionary = timelineItemsDictionary
        state.timelineState.recomputeReadMarkerUniqueID()
        
        updateRoomTaskSummary(timelineItems: timelineItems)
    }
    
    /// Collects every canvas-steps task (grouped by resolution) and every pending choice request
    /// into `TimelineViewState.roomTaskSummary`, merging two sources:
    ///
    /// 1. The timeline (below): updates after the initial message live in room state events
    ///    (canvas steps keyed by `task_id`, choice requests by the message's event ID), not in the
    ///    messages themselves, so each item's fields come from whichever is more current: the
    ///    fetched state event if one has arrived (via `fetchStateEvent`), else the message payload.
    ///    This is the only source for old-protocol rooms, which never write ask-time choice state.
    /// 2. `stateEnumeratedTasks`/`stateEnumeratedChoiceEvents` (authoritative — see
    ///    `refreshStateEnumeratedTaskSummary`): covers tasks/choices whose message hasn't been
    ///    paginated into the timeline yet, which is why the chip used to lag behind pagination.
    ///
    /// State wins on content; the two are unioned by `taskID` (tasks) / `eventID` (choices) with no
    /// duplicates.
    private func updateRoomTaskSummary(timelineItems: [RoomTimelineItemProtocol]) {
        var timelineActiveTasks = [RoomTaskSummary.Task]()
        var timelineDoneTasks = [RoomTaskSummary.Task]()
        var timelinePendingChoices = [RoomTaskSummary.PendingChoice]()
        
        for canvasItem in timelineItems.compactMap({ $0 as? AgentCanvasStepsRoomTimelineItem }) {
            guard let eventID = canvasItem.id.eventID else { continue }
            fetchStateEvent(eventType: AgentCanvasStepsRoomTimelineItemContent.msgType, stateKey: canvasItem.content.taskID)
            
            let key = StateEventKey(eventType: AgentCanvasStepsRoomTimelineItemContent.msgType, stateKey: canvasItem.content.taskID)
            let stateContent = state.fetchedStateEvents[key].flatMap { AgentCanvasStepsStateContent(parsingFrom: $0) }
            
            let steps = stateContent?.steps ?? canvasItem.content.steps
            let task = RoomTaskSummary.Task(eventID: eventID,
                                            taskID: canvasItem.content.taskID,
                                            title: stateContent?.title ?? canvasItem.content.title,
                                            isResolved: stateContent?.isResolved ?? canvasItem.content.isResolved,
                                            doneStepCount: steps.count(where: { $0.status == .done }),
                                            totalStepCount: steps.count,
                                            steps: steps,
                                            threadRootEventID: stateContent?.threadRootEventID,
                                            updatedAt: stateContent?.updatedAt)
            
            if task.isResolved {
                timelineDoneTasks.append(task)
            } else {
                timelineActiveTasks.append(task)
            }
        }
        
        for choiceItem in timelineItems.compactMap({ $0 as? AgentChoiceRequestRoomTimelineItem }) {
            guard let eventID = choiceItem.id.eventID else { continue }
            fetchStateEvent(eventType: AgentChoiceRequestRoomTimelineItemContent.msgType, stateKey: eventID)
            
            // A resolution state event with a non-empty selection, or an explicit cancellation
            // (请旨撤销), means the choice is no longer pending.
            let key = StateEventKey(eventType: AgentChoiceRequestRoomTimelineItemContent.msgType, stateKey: eventID)
            let stateContent = state.fetchedStateEvents[key].flatMap { AgentChoiceRequestStateContent(parsingFrom: $0) }
            if let stateContent, !stateContent.resolvedSelection.isEmpty || stateContent.isCancelled {
                continue
            }
            
            let question = choiceItem.content.question.isEmpty ? choiceItem.content.body : choiceItem.content.question
            timelinePendingChoices.append(.init(eventID: eventID, question: question))
        }
        
        let mergedTasks = mergeTasks(timelineTasks: timelineActiveTasks + timelineDoneTasks)
        let pendingChoices = mergePendingChoices(timelinePendingChoices: timelinePendingChoices)
        
        state.roomTaskSummary = RoomTaskSummary(activeTasks: sortedByUpdatedAtDescendingNilsLast(mergedTasks.filter { !$0.isResolved }),
                                                doneTasks: sortedByUpdatedAtDescendingNilsLast(mergedTasks.filter(\.isResolved)),
                                                pendingChoices: pendingChoices)
        
        // Mirror into the publisher feeding the task panel while it's pushed.
        if roomTaskSummarySubject.value != state.roomTaskSummary {
            roomTaskSummarySubject.send(state.roomTaskSummary)
        }
    }
    
    /// Unions the timeline-built tasks with `stateEnumeratedTasks` by `taskID`, state winning on
    /// content. A state-enumerated task's `eventID` is filled in from a matching timeline task if
    /// one is loaded, staying empty otherwise (no message paginated in yet).
    private func mergeTasks(timelineTasks: [RoomTaskSummary.Task]) -> [RoomTaskSummary.Task] {
        let eventIDsByTaskID = Dictionary(timelineTasks.map { ($0.taskID, $0.eventID) }, uniquingKeysWith: { first, _ in first })
        
        var stateTasksByTaskID = Dictionary(stateEnumeratedTasks.map { task -> (String, RoomTaskSummary.Task) in
            var task = task
            task.eventID = eventIDsByTaskID[task.taskID] ?? ""
            return (task.taskID, task)
        }, uniquingKeysWith: { first, _ in first })
        
        // Timeline order first (replacing content with the state-enumerated version where present),
        // then any tasks state alone knows about (no message paginated in yet).
        return timelineTasks.map { stateTasksByTaskID.removeValue(forKey: $0.taskID) ?? $0 } + Array(stateTasksByTaskID.values)
    }
    
    /// Unions the timeline-built pending choices with `stateEnumeratedChoiceEvents` by `eventID`.
    /// State is authoritative whenever it has an opinion at all — pending confirms/refreshes the
    /// entry, non-pending drops it even if the timeline still thinks it's pending. When state has
    /// no entry for an eventID (an old-protocol room, which never writes ask-time state), the
    /// timeline's own resolution check is trusted instead.
    private func mergePendingChoices(timelinePendingChoices: [RoomTaskSummary.PendingChoice]) -> [RoomTaskSummary.PendingChoice] {
        var pendingChoices = [RoomTaskSummary.PendingChoice]()
        for choice in timelinePendingChoices {
            if let stateEvent = stateEnumeratedChoiceEvents.first(where: { $0.eventID == choice.eventID }) {
                guard stateEvent.isPending else { continue } // State confirms this one's resolved.
                let question = stateEvent.question?.isEmpty == false ? (stateEvent.question ?? "") : choice.question
                pendingChoices.append(.init(eventID: choice.eventID, question: question))
            } else {
                pendingChoices.append(choice) // No ask-time state (old protocol) — trust the timeline.
            }
        }
        
        let handledEventIDs = Set(pendingChoices.map(\.eventID))
        for stateEvent in stateEnumeratedChoiceEvents where stateEvent.isPending && !handledEventIDs.contains(stateEvent.eventID) {
            pendingChoices.append(.init(eventID: stateEvent.eventID, question: stateEvent.question ?? ""))
        }
        
        return pendingChoices
    }
    
    /// Enumerates the room's agent task/choice state directly, independently of what's been
    /// paginated into the timeline — this is what lets the chip show up immediately on room entry
    /// rather than waiting for the relevant messages to load. Re-run (debounced) on room updates
    /// for the same reason `refreshFetchedStateEvents` is: custom state event types aren't
    /// delivered by sliding sync, so there's no push signal to react to directly.
    private func refreshStateEnumeratedTaskSummary() {
        Task {
            switch await roomProxy.getStateEventsRaw(eventType: AgentCanvasStepsRoomTimelineItemContent.msgType) {
            case .success(let rawStateEvents):
                stateEnumeratedTasks = rawStateEvents.compactMap(Self.parseCanvasTaskState)
            case .failure(let error):
                MXLog.error("Failed enumerating \(AgentCanvasStepsRoomTimelineItemContent.msgType) state events with error: \(error)")
            }
            
            switch await roomProxy.getStateEventsRaw(eventType: AgentChoiceRequestRoomTimelineItemContent.msgType) {
            case .success(let rawStateEvents):
                stateEnumeratedChoiceEvents = rawStateEvents.compactMap(AgentChoiceStateIndexEvent.init(parsingFrom:))
            case .failure(let error):
                MXLog.error("Failed enumerating \(AgentChoiceRequestRoomTimelineItemContent.msgType) state events with error: \(error)")
            }
            
            updateRoomTaskSummary(timelineItems: timelineController.timelineItems)
        }
    }
    
    /// Builds a task straight from one `io.element.agent.canvas.steps` state event's raw JSON.
    /// `AgentCanvasStepsStateContent` only looks at `content`, so the state key (the task ID) is
    /// recovered separately here. `eventID` is left empty — filled in later by `mergeTasks` if a
    /// matching timeline item is loaded.
    private static func parseCanvasTaskState(_ rawStateEventJSON: String) -> RoomTaskSummary.Task? {
        guard let taskID = stateKey(from: rawStateEventJSON),
              let content = AgentCanvasStepsStateContent(parsingFrom: rawStateEventJSON) else { return nil }
        
        return RoomTaskSummary.Task(eventID: "",
                                    taskID: taskID,
                                    title: content.title ?? "",
                                    isResolved: content.isResolved,
                                    doneStepCount: content.steps.count(where: { $0.status == .done }),
                                    totalStepCount: content.steps.count,
                                    steps: content.steps,
                                    threadRootEventID: content.threadRootEventID,
                                    updatedAt: content.updatedAt)
    }
    
    private static func stateKey(from rawStateEventJSON: String) -> String? {
        struct Envelope: Decodable {
            let stateKey: String
            private enum CodingKeys: String, CodingKey { case stateKey = "state_key" }
        }
        guard let data = rawStateEventJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Envelope.self, from: data).stateKey
    }
    
    /// Tasks without a known `updatedAt` sort after dated ones, keeping their timeline order
    /// (`sorted` is documented stable).
    private func sortedByUpdatedAtDescendingNilsLast(_ tasks: [RoomTaskSummary.Task]) -> [RoomTaskSummary.Task] {
        tasks.sorted { lhs, rhs in
            switch (lhs.updatedAt, rhs.updatedAt) {
            case let (lhsDate?, rhsDate?): lhsDate > rhsDate
            case (.some, .none): true
            default: false
            }
        }
    }
    
    private func updateViewState(item: RoomTimelineItemProtocol, groupStyle: TimelineGroupStyle) -> RoomTimelineItemViewState {
        if let timelineItemViewState = state.timelineState.itemsDictionary[item.id.uniqueID] {
            timelineItemViewState.groupStyle = groupStyle
            timelineItemViewState.type = .init(item: item)
            return timelineItemViewState
        } else {
            return RoomTimelineItemViewState(item: item, groupStyle: groupStyle)
        }
    }
    
    private func canGroupItem(timelineItem: RoomTimelineItemProtocol, with otherTimelineItem: RoomTimelineItemProtocol) -> Bool {
        if timelineItem is CollapsibleTimelineItem || otherTimelineItem is CollapsibleTimelineItem {
            return false
        }
        
        guard let eventTimelineItem = timelineItem as? EventBasedTimelineItemProtocol,
              let otherEventTimelineItem = otherTimelineItem as? EventBasedTimelineItemProtocol else {
            return false
        }
        
        // State events aren't rendered as messages so shouldn't be grouped.
        if eventTimelineItem is StateRoomTimelineItem || otherEventTimelineItem is StateRoomTimelineItem {
            return false
        }
        
        return eventTimelineItem.sender == otherEventTimelineItem.sender
            && eventTimelineItem.properties.reactions.isEmpty // Reactions break the grouping.
            && otherEventTimelineItem.timestamp.timeIntervalSince(eventTimelineItem.timestamp) < 5 * 60 // As does the passage of time.
    }
    
    /// Sets `hasNewMessagesAtBottom` to `true` when newer items arrive while the user is scrolled
    /// up in a live timeline. Skips initial load and timeline switches.
    private func updateHasNewMessagesAtBottom(with newTimelineItems: OrderedDictionary<TimelineItemIdentifier.UniqueID, RoomTimelineItemViewState>) {
        guard state.jumpToReadMarkerEnabled,
              state.timelineState.isLive,
              !state.timelineState.isSwitchingTimelines,
              !state.bindings.isScrolledToBottom,
              !state.bindings.hasNewMessagesAtBottom else {
            return
        }
        
        let oldDictionary = state.timelineState.itemsDictionary
        guard !oldDictionary.isEmpty,
              !newTimelineItems.isEmpty,
              oldDictionary.keys.last != newTimelineItems.keys.last else {
            return
        }
        
        state.bindings.hasNewMessagesAtBottom = true
    }
    
    // MARK: - Direct chats logics
    
    private let inviteLoadingIndicatorID = UUID().uuidString
    
    private func inviteOtherDMUserBack() {
        guard roomProxy.infoPublisher.value.isUserAloneInDirectRoom else {
            displayAlert(.unknown)
            return
        }
        
        Task {
            userIndicatorController.submitIndicator(.init(id: inviteLoadingIndicatorID, type: .toast, title: L10n.commonLoading))
            defer {
                userIndicatorController.retractIndicatorWithId(inviteLoadingIndicatorID)
            }
            
            guard
                let members = await roomProxy.members(),
                members.count == 2,
                let otherPerson = members.first(where: { $0.userID != roomProxy.ownUserID && $0.membership == .leave })
            else {
                displayAlert(.unknown)
                return
            }
            
            switch await roomProxy.invite(userID: otherPerson.userID) {
            case .success:
                break
            case .failure:
                displayAlert(.unableToInvite)
            }
        }
    }
    
    // MARK: - Reactions
    
    private func displayReactionSummary(for itemID: TimelineItemIdentifier, selectedKey: String) {
        guard let timelineItem = timelineController.timelineItems.firstUsingStableID(itemID),
              let eventTimelineItem = timelineItem as? EventBasedTimelineItemProtocol else {
            return
        }
        
        state.bindings.reactionSummaryInfo = .init(reactions: eventTimelineItem.properties.reactions, selectedKey: selectedKey)
    }
    
    // MARK: - Read Receipts
    
    private func displayReadReceipts(for itemID: TimelineItemIdentifier) {
        guard let timelineItem = timelineController.timelineItems.firstUsingStableID(itemID),
              let eventTimelineItem = timelineItem as? EventBasedTimelineItemProtocol else {
            return
        }
        
        state.bindings.readReceiptsSummaryInfo = .init(orderedReceipts: eventTimelineItem.properties.orderedReadReceipts, id: eventTimelineItem.id)
    }
    
    private func fetchStateEvent(eventType: String, stateKey: String) {
        let key = StateEventKey(eventType: eventType, stateKey: stateKey)
        guard state.fetchedStateEvents[key] == nil else { return }
        fetchStateEvent(key: key)
    }
    
    /// Re-fetches every state event the timeline has already asked for, picking up any changes
    /// the agent has made since. Called (debounced) on room updates because custom state event
    /// types aren't delivered by sliding sync, so there's no push signal to react to directly.
    private func refreshFetchedStateEvents() {
        for key in state.fetchedStateEvents.keys {
            fetchStateEvent(key: key)
        }
    }
    
    private func fetchStateEvent(key: StateEventKey) {
        Task {
            switch await roomProxy.getStateEventRaw(eventType: key.eventType, stateKey: key.stateKey) {
            case .success(let raw):
                // `updateValue` (not the `[key] = raw` subscript) because `raw` may be `nil` and the
                // dictionary's value type is itself `String?` — the subscript setter treats an outer
                // `nil` as "remove this key", which would erase the "already fetched" marker.
                state.fetchedStateEvents.updateValue(raw, forKey: key)
                // A freshly-fetched state event can flip a task's resolution or a choice's pending
                // status, so the room task summary needs recomputing against the now-current state.
                updateRoomTaskSummary(timelineItems: timelineController.timelineItems)
            case .failure(let error):
                MXLog.error("Failed fetching state event eventType: \(key.eventType) stateKey: \(key.stateKey) with error: \(error)")
            }
        }
    }
    
    // MARK: - Message forwarding
    
    private func forwardMessage(itemID: TimelineItemIdentifier) async {
        guard let forwardingItem = await makeForwardingItem(for: itemID) else { return }
        actionsSubject.send(.displayMessageForwarding(forwardingItem: forwardingItem))
    }
    
    // MARK: Pills
    
    private func pillContextUpdater(_ pillContext: PillContext) {
        switch pillContext.data.type {
        case let .user(id):
            let isOwnMention = id == state.ownUserID
            if let profile = state.members[id] {
                pillContext.viewState = .mention(isOwnMention: isOwnMention, displayText: PillUtilities.userPillDisplayText(username: profile.displayName, userID: id))
            } else {
                pillContext.viewState = .mention(isOwnMention: isOwnMention, displayText: id)
                pillContext.cancellable = context.$viewState
                    .compactMap { $0.members[id] }
                    .sink { [weak pillContext] profile in
                        guard let pillContext else {
                            return
                        }
                        pillContext.viewState = .mention(isOwnMention: isOwnMention, displayText: PillUtilities.userPillDisplayText(username: profile.displayName, userID: id))
                        pillContext.cancellable = nil
                    }
            }
        case .allUsers:
            pillContext.viewState = .mention(isOwnMention: true, displayText: PillUtilities.atRoom)
        case .event(let room):
            let pillViewState: PillViewState
            switch room {
            case .roomAlias(let alias):
                let roomSummary = userSession.clientProxy.roomSummaryForAlias(alias)
                pillViewState = .reference(displayText: PillUtilities.eventPillDisplayText(roomName: roomSummary?.name, rawRoomText: alias))
            case .roomID(let id):
                let roomSummary = userSession.clientProxy.roomSummaryForIdentifier(id)
                pillViewState = .reference(displayText: PillUtilities.eventPillDisplayText(roomName: roomSummary?.name, rawRoomText: id))
            }
            pillContext.viewState = pillViewState
        case .roomAlias(let alias):
            let roomSummary = userSession.clientProxy.roomSummaryForAlias(alias)
            pillContext.viewState = .reference(displayText: PillUtilities.roomPillDisplayText(roomName: roomSummary?.name, rawRoomText: alias))
        case .roomID(let id):
            let roomSummary = userSession.clientProxy.roomSummaryForIdentifier(id)
            pillContext.viewState = .reference(displayText: PillUtilities.roomPillDisplayText(roomName: roomSummary?.name, rawRoomText: id))
        }
    }
    
    // MARK: - User Indicators
    
    private func showFocusLoadingIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: Constants.focusTimelineToastIndicatorID,
                                                              type: .toast(progress: .indeterminate),
                                                              title: L10n.commonLoading,
                                                              persistent: true))
    }
    
    private func hideFocusLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(Constants.focusTimelineToastIndicatorID)
    }
    
    private func displayAlert(_ type: TimelineAlertInfoType) {
        switch type {
        case .audioRecodingPermissionError:
            state.bindings.alertInfo = .init(id: type,
                                             title: L10n.dialogPermissionMicrophoneTitleIos(InfoPlistReader.main.bundleDisplayName),
                                             message: L10n.dialogPermissionMicrophoneDescriptionIos,
                                             primaryButton: .init(title: L10n.commonSettings) { [weak self] in self?.appMediator.openAppSettings() },
                                             secondaryButton: .init(title: L10n.actionNotNow, role: .cancel, action: nil))
        case .pollEndConfirmation(let pollStartID):
            state.bindings.alertInfo = .init(id: type,
                                             title: L10n.actionEndPoll,
                                             message: L10n.commonPollEndConfirmation,
                                             primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                             secondaryButton: .init(title: L10n.actionOk) { self.timelineInteractionHandler.endPoll(pollStartID: pollStartID) })
        case .sendingFailed:
            state.bindings.alertInfo = .init(id: type,
                                             title: L10n.commonSendingFailed,
                                             primaryButton: .init(title: L10n.actionOk, action: nil))
        case .encryptionAuthenticity(let message):
            state.bindings.alertInfo = .init(id: type,
                                             title: message,
                                             primaryButton: .init(title: L10n.actionOk, action: nil))
        case .encryptionForwarder(let message):
            state.bindings.alertInfo = .init(id: type,
                                             title: message,
                                             primaryButton: .init(title: L10n.actionOk, action: nil),
                                             secondaryButton: .init(title: L10n.actionLearnMore) { [weak self] in
                                                 guard let self else { return }
                                                 appMediator.open(appSettings.historySharingDetailsURL)
                                             })
        case .inviteAgain:
            state.bindings.alertInfo = .init(id: .inviteAgain,
                                             title: L10n.screenRoomInviteAgainAlertTitle,
                                             message: L10n.screenRoomInviteAgainAlertMessage,
                                             primaryButton: .init(title: L10n.actionInvite) { [weak self] in self?.inviteOtherDMUserBack() },
                                             secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        case .unableToInvite:
            state.bindings.alertInfo = .init(id: .unableToInvite,
                                             title: L10n.commonUnableToInviteTitle,
                                             message: L10n.commonUnableToInviteMessage)
        case .unknown:
            state.bindings.alertInfo = .init(id: .unknown, title: L10n.commonError)
        }
    }
    
    private func displayErrorToast(_ title: String) {
        userIndicatorController.submitIndicator(UserIndicator(id: Constants.toastErrorID,
                                                              type: .toast,
                                                              title: title,
                                                              icon: \.close))
    }
}

// MARK: - Mocks

extension TimelineViewModel {
    static let mock = mock(timelineKind: .live)
    
    static func mock(timelineKind: TimelineKind = .live, timelineController: TimelineControllerMock? = nil, hasPredecessor: Bool = false) -> TimelineViewModel {
        let clientProxyMock = ClientProxyMock(.init())
        clientProxyMock.roomSummaryForAliasReturnValue = .mock(id: "!room:matrix.org", name: "Room")
        clientProxyMock.roomSummaryForIdentifierReturnValue = .mock(id: "!room:matrix.org", name: "Room", canonicalAlias: "#room:matrix.org")
        let roomProxy = JoinedRoomProxyMock(.init(name: "Preview room", predecessor: hasPredecessor ? .init(roomId: UUID().uuidString) : nil))
        
        let appSettings = AppSettings.volatile()
        
        return TimelineViewModel(roomProxy: roomProxy,
                                 focussedEventID: nil,
                                 timelineController: timelineController ?? TimelineControllerMock(.init(timelineKind: timelineKind)),
                                 userSession: UserSessionMock(.init(clientProxy: clientProxyMock)),
                                 mediaPlayerProvider: MediaPlayerProviderMock(),
                                 userIndicatorController: UserIndicatorControllerMock(),
                                 appMediator: AppMediatorMock(.init()),
                                 appSettings: appSettings,
                                 analyticsService: AnalyticsServiceMock(.init()),
                                 emojiProvider: EmojiProvider(appSettings: appSettings),
                                 linkMetadataProvider: LinkMetadataProvider(),
                                 timelineControllerFactory: TimelineControllerFactoryMock(.init()))
    }
}

extension EnvironmentValues {
    /// Used to access and inject the room context without observing it
    @Entry var timelineContext: TimelineViewModel.Context?
    /// An event ID which will be non-nil when a timeline item should show as focussed.
    @Entry var focussedEventID: String?
}

private enum SlashCommand: String, CaseIterable {
    case join = "/join "
}
