//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

@MainActor
final class TimelineViewModelTests {
    var cancellables = Set<AnyCancellable>()
    
    init() async throws {
        cancellables.removeAll()
    }
    
    // MARK: - Message Grouping
    
    @Test
    func messageGrouping() {
        // Given 3 messages from Bob.
        let items = [
            TextRoomTimelineItem(text: "Message 1",
                                 sender: "bob"),
            TextRoomTimelineItem(text: "Message 2",
                                 sender: "bob"),
            TextRoomTimelineItem(text: "Message 3",
                                 sender: "bob")
        ]
        
        // When showing them in a timeline.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // Then the messages should be grouped together.
        #expect(viewModel.state.timelineState.itemViewStates[0].groupStyle == .first, "Nothing should prevent the first message from being grouped.")
        #expect(viewModel.state.timelineState.itemViewStates[1].groupStyle == .middle, "Nothing should prevent the middle message from being grouped.")
        #expect(viewModel.state.timelineState.itemViewStates[2].groupStyle == .last, "Nothing should prevent the last message from being grouped.")
    }
    
    @Test
    func messageGroupingMultipleSenders() {
        // Given some interleaved messages from Bob and Alice.
        let items = [
            TextRoomTimelineItem(text: "Message 1",
                                 sender: "alice"),
            TextRoomTimelineItem(text: "Message 2",
                                 sender: "bob"),
            TextRoomTimelineItem(text: "Message 3",
                                 sender: "alice"),
            TextRoomTimelineItem(text: "Message 4",
                                 sender: "alice"),
            TextRoomTimelineItem(text: "Message 5",
                                 sender: "bob"),
            TextRoomTimelineItem(text: "Message 6",
                                 sender: "bob")
        ]
        
        // When showing them in a timeline.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // Then the messages should be grouped by sender.
        #expect(viewModel.state.timelineState.itemViewStates[0].groupStyle == .single, "A message should not be grouped when the sender changes.")
        #expect(viewModel.state.timelineState.itemViewStates[1].groupStyle == .single, "A message should not be grouped when the sender changes.")
        #expect(viewModel.state.timelineState.itemViewStates[2].groupStyle == .first, "A group should start with a new sender if there are more messages from that sender.")
        #expect(viewModel.state.timelineState.itemViewStates[3].groupStyle == .last, "A group should be ended when the sender changes in the next message.")
        #expect(viewModel.state.timelineState.itemViewStates[4].groupStyle == .first, "A group should start with a new sender if there are more messages from that sender.")
        #expect(viewModel.state.timelineState.itemViewStates[5].groupStyle == .last, "A group should be ended when the sender changes in the next message.")
    }
    
    @Test
    func messageGroupingWithLeadingReactions() {
        // Given 3 messages from Bob where the first message has a reaction.
        let items = [
            TextRoomTimelineItem(text: "Message 1",
                                 sender: "bob",
                                 addReactions: true),
            TextRoomTimelineItem(text: "Message 2",
                                 sender: "bob"),
            TextRoomTimelineItem(text: "Message 3",
                                 sender: "bob")
        ]
        
        // When showing them in a timeline.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // Then the first message should not be grouped but the other two should.
        #expect(viewModel.state.timelineState.itemViewStates[0].groupStyle == .single, "When the first message has reactions it should not be grouped.")
        #expect(viewModel.state.timelineState.itemViewStates[1].groupStyle == .first, "A new group should be made when the preceding message has reactions.")
        #expect(viewModel.state.timelineState.itemViewStates[2].groupStyle == .last, "Nothing should prevent the last message from being grouped.")
    }
    
    @Test
    func messageGroupingWithInnerReactions() {
        // Given 3 messages from Bob where the middle message has a reaction.
        let items = [
            TextRoomTimelineItem(text: "Message 1",
                                 sender: "bob"),
            TextRoomTimelineItem(text: "Message 2",
                                 sender: "bob",
                                 addReactions: true),
            TextRoomTimelineItem(text: "Message 3",
                                 sender: "bob")
        ]
        
        // When showing them in a timeline.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // Then the first and second messages should be grouped and the last one should not.
        #expect(viewModel.state.timelineState.itemViewStates[0].groupStyle == .first, "Nothing should prevent the first message from being grouped.")
        #expect(viewModel.state.timelineState.itemViewStates[1].groupStyle == .last, "When the message has reactions, the group should end here.")
        #expect(viewModel.state.timelineState.itemViewStates[2].groupStyle == .single, "The last message should not be grouped when the preceding message has reactions.")
    }
    
    @Test
    func messageGroupingWithTrailingReactions() {
        // Given 3 messages from Bob where the last message has a reaction.
        let items = [
            TextRoomTimelineItem(text: "Message 1",
                                 sender: "bob"),
            TextRoomTimelineItem(text: "Message 2",
                                 sender: "bob"),
            TextRoomTimelineItem(text: "Message 3",
                                 sender: "bob",
                                 addReactions: true)
        ]
        
        // When showing them in a timeline.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // Then the messages should be grouped together.
        #expect(viewModel.state.timelineState.itemViewStates[0].groupStyle == .first, "Nothing should prevent the first message from being grouped.")
        #expect(viewModel.state.timelineState.itemViewStates[1].groupStyle == .middle, "Nothing should prevent the second message from being grouped.")
        #expect(viewModel.state.timelineState.itemViewStates[2].groupStyle == .last, "Reactions on the last message should not prevent it from being grouped.")
    }
    
    // MARK: - Focussing
    
    @Test
    func focusItem() async throws {
        // Given a room with 3 items loaded in a live timeline.
        let items = [TextRoomTimelineItem(eventID: "t1"),
                     TextRoomTimelineItem(eventID: "t2"),
                     TextRoomTimelineItem(eventID: "t3")]
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        
        let viewModel = makeViewModel(timelineController: timelineController)
        #expect(timelineController.focusOnEventTimelineSizeCallsCount == 0)
        #expect(viewModel.context.viewState.timelineState.isLive)
        #expect(viewModel.context.viewState.timelineState.focussedEvent == nil)
        
        // When focussing on an item that isn't loaded.
        let deferred = deferFulfillment(viewModel.context.$viewState) { !$0.timelineState.isLive }
        await viewModel.focusOnEvent(eventID: "t4")
        try await deferred.fulfill()
        
        // Then a new timeline should be loaded and the room focussed on that event.
        #expect(timelineController.focusOnEventTimelineSizeCallsCount == 1)
        #expect(!viewModel.context.viewState.timelineState.isLive)
        #expect(viewModel.context.viewState.timelineState.focussedEvent == .init(eventID: "t4", appearance: .immediate))
    }
    
    @Test
    func focusLoadedItem() async throws {
        // Given a room with 3 items loaded in a live timeline.
        let items = [TextRoomTimelineItem(eventID: "t1"),
                     TextRoomTimelineItem(eventID: "t2"),
                     TextRoomTimelineItem(eventID: "t3")]
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        
        let viewModel = makeViewModel(timelineController: timelineController)
        #expect(timelineController.focusOnEventTimelineSizeCallsCount == 0)
        #expect(viewModel.context.viewState.timelineState.isLive)
        #expect(viewModel.context.viewState.timelineState.focussedEvent == nil)
        
        // When focussing on a loaded item.
        let deferred = deferFailure(viewModel.context.$viewState, timeout: .seconds(1)) { !$0.timelineState.isLive }
        await viewModel.focusOnEvent(eventID: "t1")
        try await deferred.fulfill()
        
        // Then the timeline should remain live and the item should be focussed.
        #expect(timelineController.focusOnEventTimelineSizeCallsCount == 0)
        #expect(viewModel.context.viewState.timelineState.isLive)
        #expect(viewModel.context.viewState.timelineState.focussedEvent == .init(eventID: "t1", appearance: .animated))
    }
    
    @Test
    func focusLive() async throws {
        // Given a room with a non-live timeline focussed on a particular event.
        let items = [TextRoomTimelineItem(eventID: "t1"),
                     TextRoomTimelineItem(eventID: "t2"),
                     TextRoomTimelineItem(eventID: "t3")]
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        
        let viewModel = makeViewModel(timelineController: timelineController)
        
        var deferred = deferFulfillment(viewModel.context.$viewState) { !$0.timelineState.isLive }
        await viewModel.focusOnEvent(eventID: "t4")
        try await deferred.fulfill()
        
        #expect(timelineController.focusLiveCallsCount == 0)
        #expect(!viewModel.context.viewState.timelineState.isLive)
        #expect(viewModel.context.viewState.timelineState.focussedEvent == .init(eventID: "t4", appearance: .immediate))
        
        // When switching back to a live timeline.
        deferred = deferFulfillment(viewModel.context.$viewState) { $0.timelineState.isLive }
        viewModel.context.send(viewAction: .focusLive)
        try await deferred.fulfill()
        
        // Then the timeline should switch back to being live and the event focus should be removed.
        #expect(timelineController.focusLiveCallsCount == 1)
        #expect(viewModel.context.viewState.timelineState.isLive)
        #expect(viewModel.context.viewState.timelineState.focussedEvent == nil)
    }
    
    @Test
    func initialFocusViewState() {
        let timelineController = TimelineControllerMock(.init())
        
        let viewModel = makeViewModel(focussedEventID: "t10", timelineController: timelineController)
        #expect(viewModel.context.viewState.timelineState.focussedEvent == .init(eventID: "t10", appearance: .immediate))
    }
    
    // MARK: - Read Receipts
    
    @Test
    func sendReadReceipt() async throws {
        // Given a room with only text items in the timeline
        let items = [TextRoomTimelineItem(eventID: "t1"),
                     TextRoomTimelineItem(eventID: "t2"),
                     TextRoomTimelineItem(eventID: "t3")]
        let (viewModel, _, timelineProxy, _) = readReceiptsConfiguration(with: items)
        
        // When sending a read receipt for the last item.
        try viewModel.context.send(viewAction: .sendReadReceiptIfNeeded(#require(items.last?.id)))
        try await Task.sleep(for: .milliseconds(100))
        
        // Then the receipt should be sent.
        #expect(timelineProxy.sendReadReceiptForTypeCalled == true)
        let arguments = timelineProxy.sendReadReceiptForTypeReceivedArguments
        #expect(arguments?.eventID == "t3")
        #expect(arguments?.type == .read)
    }
    
    @Test
    func sendReadReceiptWithoutEvents() async throws {
        // Given a room with only virtual items.
        let items = [SeparatorRoomTimelineItem(uniqueID: .init("v1")),
                     SeparatorRoomTimelineItem(uniqueID: .init("v2")),
                     SeparatorRoomTimelineItem(uniqueID: .init("v3"))]
        let (viewModel, _, timelineProxy, _) = readReceiptsConfiguration(with: items)
        
        // When sending a read receipt for the last item.
        try viewModel.context.send(viewAction: .sendReadReceiptIfNeeded(#require(items.last?.id)))
        try await Task.sleep(for: .milliseconds(100))
        
        // Then nothing should be sent.
        #expect(timelineProxy.sendReadReceiptForTypeCalled == false)
    }
    
    @Test
    func sendReadReceiptVirtualLast() async throws {
        // Given a room where the last event is a virtual item.
        let items: [RoomTimelineItemProtocol] = [TextRoomTimelineItem(eventID: "t1"),
                                                 TextRoomTimelineItem(eventID: "t2"),
                                                 SeparatorRoomTimelineItem(uniqueID: .init("v3"))]
        let (viewModel, _, _, _) = readReceiptsConfiguration(with: items)
        
        // When sending a read receipt for the last item.
        try viewModel.context.send(viewAction: .sendReadReceiptIfNeeded(#require(items.last?.id)))
        try await Task.sleep(for: .milliseconds(100))
    }
    
    // swiftlint:disable:next large_tuple
    private func readReceiptsConfiguration(with items: [RoomTimelineItemProtocol]) -> (TimelineViewModel,
                                                                                       JoinedRoomProxyMock,
                                                                                       TimelineProxyMock,
                                                                                       TimelineControllerMock) {
        let timelineProxy = TimelineProxyMock()
        timelineProxy.sendReadReceiptForTypeReturnValue = .success(())
        
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.timeline = timelineProxy
        
        let timelineController = TimelineControllerMock(.init(roomProxy: roomProxy, timelineItems: items))
        
        let appSettings = AppSettings.volatile()
        
        let viewModel = TimelineViewModel(roomProxy: roomProxy,
                                          timelineController: timelineController,
                                          userSession: UserSessionMock(.init()),
                                          mediaPlayerProvider: MediaPlayerProviderMock(),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          appMediator: AppMediatorMock(.init()),
                                          appSettings: appSettings,
                                          analyticsService: AnalyticsServiceMock(.init()),
                                          emojiProvider: EmojiProvider(appSettings: appSettings),
                                          linkMetadataProvider: LinkMetadataProvider(),
                                          timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        return (viewModel, roomProxy, timelineProxy, timelineController)
    }
    
    @Test
    func showReadReceipts() async throws {
        let receipts: [ReadReceipt] = [.init(userID: "@alice:matrix.org", formattedTimestamp: "12:00"),
                                       .init(userID: "@charlie:matrix.org", formattedTimestamp: "11:00")]
        // Given 3 messages from Bob where the middle message has a reaction.
        let message = TextRoomTimelineItem(text: "Test",
                                           sender: "bob",
                                           addReadReceipts: receipts)
        let id = message.id
        
        let appSettings = AppSettings.volatile()
        
        // When showing them in a timeline.
        let timelineController = TimelineControllerMock(.init(timelineItems: [message]))
        let viewModel = TimelineViewModel(roomProxy: JoinedRoomProxyMock(.init(name: "", members: [RoomMemberProxyMock.mockAlice, RoomMemberProxyMock.mockCharlie])),
                                          timelineController: timelineController,
                                          userSession: UserSessionMock(.init()),
                                          mediaPlayerProvider: MediaPlayerProviderMock(),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          appMediator: AppMediatorMock(.init()),
                                          appSettings: appSettings,
                                          analyticsService: AnalyticsServiceMock(.init()),
                                          emojiProvider: EmojiProvider(appSettings: appSettings),
                                          linkMetadataProvider: LinkMetadataProvider(),
                                          timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        
        let deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.bindings.readReceiptsSummaryInfo?.orderedReceipts == receipts
        }
        
        viewModel.context.send(viewAction: .displayReadReceipts(itemID: id))
        try await deferred.fulfill()
    }
    
    @Test
    func showManageUserAsAdmin() async throws {
        let appSettings = AppSettings.volatile()
        
        let viewModel = TimelineViewModel(roomProxy: JoinedRoomProxyMock(.init(name: "",
                                                                               members: [RoomMemberProxyMock.mockAdmin,
                                                                                         RoomMemberProxyMock.mockAlice],
                                                                               ownUserID: RoomMemberProxyMock.mockAdmin.userID)),
                                          timelineController: TimelineControllerMock(.init()),
                                          userSession: UserSessionMock(.init()),
                                          mediaPlayerProvider: MediaPlayerProviderMock(),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          appMediator: AppMediatorMock(.init()),
                                          appSettings: appSettings,
                                          analyticsService: AnalyticsServiceMock(.init()),
                                          emojiProvider: EmojiProvider(appSettings: appSettings),
                                          linkMetadataProvider: LinkMetadataProvider(),
                                          timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        
        var deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.canCurrentUserKick && value.canCurrentUserBan
        }
        
        try await deferred.fulfill()
        
        deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.bindings.manageMemberViewModel != nil
        }
        
        viewModel.context.send(viewAction: .tappedOnSenderDetails(sender: .init(with: RoomMemberProxyMock.mockAlice)))
        try await deferred.fulfill()
        
        #expect(viewModel.context.manageMemberViewModel?.id == RoomMemberProxyMock.mockAlice.userID)
        #expect(viewModel.context.manageMemberViewModel?.state.permissions.canBan == true)
        #expect(viewModel.context.manageMemberViewModel?.state.permissions.canKick == true)
        #expect(viewModel.context.manageMemberViewModel?.state.isKickDisabled == false)
        #expect(viewModel.context.manageMemberViewModel?.state.isBanUnbanDisabled == false)
    }
    
    @Test
    func showDetailsForAnAdmin() async throws {
        let appSettings = AppSettings.volatile()
        
        let viewModel = TimelineViewModel(roomProxy: JoinedRoomProxyMock(.init(name: "",
                                                                               members: [RoomMemberProxyMock.mockAdmin,
                                                                                         RoomMemberProxyMock.mockAlice],
                                                                               ownUserID: RoomMemberProxyMock.mockAlice.userID)),
                                          timelineController: TimelineControllerMock(.init()),
                                          userSession: UserSessionMock(.init()),
                                          mediaPlayerProvider: MediaPlayerProviderMock(),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          appMediator: AppMediatorMock(.init()),
                                          appSettings: appSettings,
                                          analyticsService: AnalyticsServiceMock(.init()),
                                          emojiProvider: EmojiProvider(appSettings: appSettings),
                                          linkMetadataProvider: LinkMetadataProvider(),
                                          timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        
        var deferredState = deferFulfillment(viewModel.context.$viewState) { value in
            !value.canCurrentUserKick && !value.canCurrentUserBan
        }
        
        try await deferredState.fulfill()
        
        deferredState = deferFulfillment(viewModel.context.$viewState) { value in
            value.bindings.manageMemberViewModel != nil
        }
        
        viewModel.context.send(viewAction: .tappedOnSenderDetails(sender: .init(with: RoomMemberProxyMock.mockAdmin)))
        try await deferredState.fulfill()
        
        #expect(viewModel.context.manageMemberViewModel?.state.permissions.canBan == false)
        #expect(viewModel.context.manageMemberViewModel?.state.permissions.canKick == false)
        #expect(viewModel.context.manageMemberViewModel?.state.isKickDisabled == true)
        #expect(viewModel.context.manageMemberViewModel?.state.isBanUnbanDisabled == true)
        #expect(viewModel.context.manageMemberViewModel?.id == RoomMemberProxyMock.mockAdmin.userID)
    }
    
    @Test
    func showDetailsForABannedUser() async throws {
        let appSettings = AppSettings.volatile()
        
        let viewModel = TimelineViewModel(roomProxy: JoinedRoomProxyMock(.init(name: "",
                                                                               members: [RoomMemberProxyMock.mockAdmin,
                                                                                         RoomMemberProxyMock.mockBanned[0]],
                                                                               ownUserID: RoomMemberProxyMock.mockAdmin.userID)),
                                          timelineController: TimelineControllerMock(.init()),
                                          userSession: UserSessionMock(.init()),
                                          mediaPlayerProvider: MediaPlayerProviderMock(),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          appMediator: AppMediatorMock(.init()),
                                          appSettings: appSettings,
                                          analyticsService: AnalyticsServiceMock(.init()),
                                          emojiProvider: EmojiProvider(appSettings: appSettings),
                                          linkMetadataProvider: LinkMetadataProvider(),
                                          timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        
        var deferredState = deferFulfillment(viewModel.context.$viewState) { value in
            value.canCurrentUserKick && value.canCurrentUserBan
        }
        
        try await deferredState.fulfill()
        
        deferredState = deferFulfillment(viewModel.context.$viewState) { value in
            value.bindings.manageMemberViewModel != nil
        }
        
        viewModel.context.send(viewAction: .tappedOnSenderDetails(sender: .init(with: RoomMemberProxyMock.mockBanned[0])))
        try await deferredState.fulfill()
        
        #expect(viewModel.context.manageMemberViewModel?.state.permissions.canBan == true)
        #expect(viewModel.context.manageMemberViewModel?.state.permissions.canKick == true)
        #expect(viewModel.context.manageMemberViewModel?.state.isKickDisabled == true)
        #expect(viewModel.context.manageMemberViewModel?.state.isBanUnbanDisabled == false)
        #expect(viewModel.context.manageMemberViewModel?.state.isMemberBanned == true)
        #expect(viewModel.context.manageMemberViewModel?.id == RoomMemberProxyMock.mockBanned[0].userID)
    }
    
    // MARK: - Room Task Summary
    
    @Test
    func canvasTasksAreGroupedByResolution() {
        // Given a timeline with a resolved canvas task followed by an unresolved one.
        let items: [RoomTimelineItemProtocol] = [
            AgentCanvasStepsRoomTimelineItem(eventID: "resolved-task", taskID: "task-1", title: "Old task", isResolved: true),
            TextRoomTimelineItem(eventID: "t1"),
            AgentCanvasStepsRoomTimelineItem(eventID: "unresolved-task", taskID: "task-2", title: "New task", isResolved: false)
        ]
        
        // When showing them in a timeline.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // Then the summary should group the unresolved task as active and the resolved one as done.
        #expect(viewModel.state.roomTaskSummary.activeTasks.map(\.eventID) == ["unresolved-task"])
        #expect(viewModel.state.roomTaskSummary.activeTasks.first?.taskID == "task-2")
        #expect(viewModel.state.roomTaskSummary.activeTasks.first?.title == "New task")
        #expect(viewModel.state.roomTaskSummary.doneTasks.map(\.eventID) == ["resolved-task"])
        #expect(viewModel.state.roomTaskSummary.doneTasks.first?.title == "Old task")
    }
    
    @Test
    func messageOnlyTaskUsesMessagePayload() {
        // Given a canvas task whose only source of truth is its message (no state event fetched yet).
        let steps = [CanvasStep(id: "s1", label: "One", status: .done),
                     CanvasStep(id: "s2", label: "Two", status: .inProgress),
                     CanvasStep(id: "s3", label: "Three", status: .pending)]
        let items = [
            AgentCanvasStepsRoomTimelineItem(eventID: "task-message", taskID: "task-1", title: "Message title", isResolved: false, steps: steps)
        ]
        
        // When showing it in a timeline.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // Then every summary field should come from the message payload, with the
        // state-event-only fields left nil.
        let task = viewModel.state.roomTaskSummary.activeTasks.first
        #expect(task?.eventID == "task-message")
        #expect(task?.taskID == "task-1")
        #expect(task?.title == "Message title")
        #expect(task?.steps == steps)
        #expect(task?.doneStepCount == 1)
        #expect(task?.totalStepCount == 3)
        #expect(task?.threadRootEventID == nil)
        #expect(task?.updatedAt == nil)
    }
    
    @Test
    func stateEventFieldsOverrideMessagePayload() async throws {
        // Given a canvas task whose state event has moved on from the initial message.
        let items = [
            AgentCanvasStepsRoomTimelineItem(eventID: "task-message", taskID: "task-1", title: "Message title", isResolved: false)
        ]
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getStateEventRawEventTypeStateKeyClosure = { eventType, stateKey in
            guard eventType == AgentCanvasStepsRoomTimelineItemContent.msgType, stateKey == "task-1" else { return .success(nil) }
            return .success("""
            {"type":"io.element.agent.canvas.steps","state_key":"task-1",
            "content":{"status":"in_progress","title":"State title","thread_root_id":"$thread-root","updated_at":2000,
            "steps":[{"id":"s1","label":"One","status":"done"},{"id":"s2","label":"Two","status":"pending"}]}}
            """)
        }
        
        // When showing it in a timeline and the state event arrives.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(roomProxy: roomProxy, timelineController: timelineController)
        
        let deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.roomTaskSummary.activeTasks.first?.title == "State title"
        }
        try await deferred.fulfill()
        
        // Then the state event's fields should win over the message payload.
        let task = try #require(viewModel.state.roomTaskSummary.activeTasks.first)
        #expect(task.eventID == "task-message")
        #expect(task.threadRootEventID == "$thread-root")
        #expect(task.updatedAt == Date(timeIntervalSince1970: 2))
        #expect(task.doneStepCount == 1)
        #expect(task.totalStepCount == 2)
    }
    
    @Test
    func onlyDoneCanvasTasksLeaveNoActiveTasks() {
        // Given a timeline with only a resolved canvas task.
        let items = [
            AgentCanvasStepsRoomTimelineItem(eventID: "resolved-task", taskID: "task-1", title: "Old task", isResolved: true)
        ]
        
        // When showing them in a timeline.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // Then there should be no active tasks but the summary shouldn't be empty either.
        #expect(viewModel.state.roomTaskSummary.activeTasks.isEmpty)
        #expect(viewModel.state.roomTaskSummary.doneTasks.map(\.eventID) == ["resolved-task"])
        #expect(!viewModel.state.roomTaskSummary.isEmpty)
    }
    
    @Test
    func activeTasksAreSortedByUpdatedAtDescendingWithNilsLast() async throws {
        // Given three unresolved tasks: an older update, a newer update and one with no state event.
        let items: [RoomTimelineItemProtocol] = [
            AgentCanvasStepsRoomTimelineItem(eventID: "early-task", taskID: "task-early", title: "Early", isResolved: false),
            AgentCanvasStepsRoomTimelineItem(eventID: "late-task", taskID: "task-late", title: "Late", isResolved: false),
            AgentCanvasStepsRoomTimelineItem(eventID: "undated-task", taskID: "task-undated", title: "Undated", isResolved: false)
        ]
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getStateEventRawEventTypeStateKeyClosure = { eventType, stateKey in
            guard eventType == AgentCanvasStepsRoomTimelineItemContent.msgType else { return .success(nil) }
            switch stateKey {
            case "task-early": return .success(#"{"content":{"status":"in_progress","updated_at":1000}}"#)
            case "task-late": return .success(#"{"content":{"status":"in_progress","updated_at":2000}}"#)
            default: return .success(nil)
            }
        }
        
        // When showing them in a timeline and both state events arrive.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(roomProxy: roomProxy, timelineController: timelineController)
        
        // Then the most recently updated task should come first, with the undated one last.
        let deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.roomTaskSummary.activeTasks.map(\.taskID) == ["task-late", "task-early", "task-undated"]
        }
        try await deferred.fulfill()
    }
    
    @Test
    func onlyUnresolvedChoiceRequestsArePending() async throws {
        // Given two choice requests, one already answered via its resolution state event. The
        // pending one has no question so its body should be used instead.
        let items: [RoomTimelineItemProtocol] = [
            AgentChoiceRequestRoomTimelineItem(eventID: "choice-resolved", question: "Answered?"),
            AgentChoiceRequestRoomTimelineItem(eventID: "choice-pending", question: "", body: "Fallback question")
        ]
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getStateEventRawEventTypeStateKeyClosure = { eventType, stateKey in
            guard eventType == AgentChoiceRequestRoomTimelineItemContent.msgType, stateKey == "choice-resolved" else { return .success(nil) }
            return .success(#"{"content":{"resolved_selection":["option-1"]}}"#)
        }
        
        // When showing them in a timeline and the resolution state event arrives.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(roomProxy: roomProxy, timelineController: timelineController)
        
        // Then only the unanswered request should be pending, using its body as the question.
        let deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.roomTaskSummary.pendingChoices.map(\.eventID) == ["choice-pending"]
        }
        try await deferred.fulfill()
        
        #expect(viewModel.state.roomTaskSummary.pendingChoices.first?.question == "Fallback question")
    }
    
    @Test
    func chipTapWithSingleActiveTaskGoesStraightToDetail() async throws {
        // Given a timeline whose summary holds exactly one active task and nothing else.
        let items = [
            AgentCanvasStepsRoomTimelineItem(eventID: "only-task", taskID: "task-1", title: "Only task", isResolved: false)
        ]
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // When tapping the progress chip.
        let deferred = deferFulfillment(viewModel.actions) { action in
            guard case .presentCanvasSteps(let eventID, let taskID) = action else { return false }
            return eventID == "only-task" && taskID == "task-1"
        }
        viewModel.process(viewAction: .tappedRoomTaskChip)
        
        // Then the smart shortcut should skip the panel and push the task's detail.
        try await deferred.fulfill()
    }
    
    @Test
    func chipTapWithMultipleActiveTasksOpensTaskPanel() async throws {
        // Given a timeline with more than one active task.
        let items: [RoomTimelineItemProtocol] = [
            AgentCanvasStepsRoomTimelineItem(eventID: "task-a", taskID: "task-1", title: "A", isResolved: false),
            AgentCanvasStepsRoomTimelineItem(eventID: "task-b", taskID: "task-2", title: "B", isResolved: false)
        ]
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // When tapping the progress chip.
        let deferred = deferFulfillment(viewModel.actions) { action in
            guard case .presentTaskPanel = action else { return false }
            return true
        }
        viewModel.process(viewAction: .tappedRoomTaskChip)
        
        // Then the task panel should be presented instead of a single detail.
        try await deferred.fulfill()
    }
    
    @Test
    func chipTapWithActiveTaskAndPendingChoiceOpensTaskPanel() async throws {
        // Given a single active task accompanied by a pending choice request.
        let items: [RoomTimelineItemProtocol] = [
            AgentCanvasStepsRoomTimelineItem(eventID: "only-task", taskID: "task-1", title: "Only task", isResolved: false),
            AgentChoiceRequestRoomTimelineItem(eventID: "choice-pending", question: "Deploy?")
        ]
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // When tapping the progress chip.
        let deferred = deferFulfillment(viewModel.actions) { action in
            guard case .presentTaskPanel = action else { return false }
            return true
        }
        viewModel.process(viewAction: .tappedRoomTaskChip)
        
        // Then the pending choice should force the panel even with one active task.
        try await deferred.fulfill()
    }
    
    @Test
    func chipTapWithActiveAndDoneTasksOpensTaskPanel() async throws {
        // Given a single active task alongside an already-resolved one.
        let items: [RoomTimelineItemProtocol] = [
            AgentCanvasStepsRoomTimelineItem(eventID: "done-task", taskID: "task-1", title: "Done", isResolved: true),
            AgentCanvasStepsRoomTimelineItem(eventID: "active-task", taskID: "task-2", title: "Active", isResolved: false)
        ]
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // When tapping the progress chip.
        let deferred = deferFulfillment(viewModel.actions) { action in
            guard case .presentTaskPanel = action else { return false }
            return true
        }
        viewModel.process(viewAction: .tappedRoomTaskChip)
        
        // Then the done task should count towards the panel threshold.
        try await deferred.fulfill()
    }
    
    @Test
    func roomTaskSummaryPublisherMirrorsViewState() {
        // Given a timeline with an active task.
        let items = [
            AgentCanvasStepsRoomTimelineItem(eventID: "only-task", taskID: "task-1", title: "Only task", isResolved: false)
        ]
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // Then the publisher feeding the task panel should carry the same summary as the view state.
        #expect(viewModel.roomTaskSummaryPublisher.value == viewModel.state.roomTaskSummary)
        #expect(viewModel.roomTaskSummaryPublisher.value.activeTasks.map(\.eventID) == ["only-task"])
    }
    
    @Test
    func summaryIsEmptyWithoutAgentItems() {
        // Given a timeline without any agent items.
        let items = [TextRoomTimelineItem(eventID: "t1")]
        
        // When showing them in a timeline.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        // Then the summary should be empty.
        #expect(viewModel.state.roomTaskSummary.isEmpty)
    }
    
    // MARK: - Room Task Summary (state enumeration)
    
    @Test
    func stateOnlyTaskAppearsWithoutTimelineItem() async throws {
        // Given a room whose only knowledge of a canvas task lives in room state — its presenting
        // message hasn't been paginated into the timeline.
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getStateEventsRawEventTypeClosure = { eventType in
            guard eventType == AgentCanvasStepsRoomTimelineItemContent.msgType else { return .success([]) }
            return .success(["""
            {"type":"io.element.agent.canvas.steps","state_key":"task-state-only",
            "content":{"status":"in_progress","title":"State-only task",
            "steps":[{"id":"s1","label":"One","status":"done"}]}}
            """])
        }
        
        // When showing an empty timeline and enumerating room state.
        let timelineController = TimelineControllerMock(.init(timelineItems: []))
        let viewModel = makeViewModel(roomProxy: roomProxy, timelineController: timelineController)
        
        // Then the chip's summary should carry the task straight from state, with no event ID.
        let deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.roomTaskSummary.activeTasks.map(\.taskID) == ["task-state-only"]
        }
        try await deferred.fulfill()
        
        let task = try #require(viewModel.state.roomTaskSummary.activeTasks.first)
        #expect(task.eventID.isEmpty)
        #expect(task.title == "State-only task")
        #expect(task.doneStepCount == 1)
        #expect(task.totalStepCount == 1)
    }
    
    @Test
    func stateAndMessageTaskAreMergedNotDuplicated() async throws {
        // Given a canvas task present both as a loaded timeline message and in room state, where
        // state has moved on to a different title and resolution.
        let items = [
            AgentCanvasStepsRoomTimelineItem(eventID: "task-message", taskID: "task-1", title: "Message title", isResolved: false)
        ]
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getStateEventsRawEventTypeClosure = { eventType in
            guard eventType == AgentCanvasStepsRoomTimelineItemContent.msgType else { return .success([]) }
            return .success(["""
            {"type":"io.element.agent.canvas.steps","state_key":"task-1",
            "content":{"status":"done","title":"State title","steps":[{"id":"s1","label":"One","status":"done"}]}}
            """])
        }
        
        // When showing the timeline and enumerating room state.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(roomProxy: roomProxy, timelineController: timelineController)
        
        // Then exactly one merged task should appear (no duplicate), resolved per state, keeping
        // the presenting message's event ID.
        let deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.roomTaskSummary.doneTasks.map(\.taskID) == ["task-1"]
        }
        try await deferred.fulfill()
        
        #expect(viewModel.state.roomTaskSummary.activeTasks.isEmpty)
        let task = try #require(viewModel.state.roomTaskSummary.doneTasks.first)
        #expect(task.eventID == "task-message")
        #expect(task.title == "State title")
    }
    
    @Test
    func stateOnlyPendingChoiceAppearsWithoutTimelineItem() async throws {
        // Given a room whose only knowledge of a choice request lives in room state (no ask-time
        // message paginated in), with its ask-time state present and still pending.
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getStateEventsRawEventTypeClosure = { eventType in
            guard eventType == AgentChoiceRequestRoomTimelineItemContent.msgType else { return .success([]) }
            return .success(["""
            {"type":"io.element.agent.choice_request","state_key":"choice-state-only",
            "content":{"status":"pending","question":"Deploy to prod?","resolved_selection":[]}}
            """])
        }
        
        // When showing an empty timeline and enumerating room state.
        let timelineController = TimelineControllerMock(.init(timelineItems: []))
        let viewModel = makeViewModel(roomProxy: roomProxy, timelineController: timelineController)
        
        // Then the pending choice should appear, sourced entirely from state.
        let deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.roomTaskSummary.pendingChoices.map(\.eventID) == ["choice-state-only"]
        }
        try await deferred.fulfill()
        
        #expect(viewModel.state.roomTaskSummary.pendingChoices.first?.question == "Deploy to prod?")
    }
    
    @Test
    func stateConfirmedResolvedChoiceOverridesTimelinePendingGuess() async throws {
        // Given a choice request the timeline alone would still call pending (no per-key state
        // fetch configured), but full state enumeration confirms it's already been answered.
        let items = [
            AgentChoiceRequestRoomTimelineItem(eventID: "choice-1", question: "Deploy?")
        ]
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getStateEventsRawEventTypeClosure = { eventType in
            guard eventType == AgentChoiceRequestRoomTimelineItemContent.msgType else { return .success([]) }
            return .success(["""
            {"type":"io.element.agent.choice_request","state_key":"choice-1",
            "content":{"status":"resolved","question":"Deploy?","resolved_selection":["option-1"]}}
            """])
        }
        
        // When showing the timeline and enumerating room state.
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(roomProxy: roomProxy, timelineController: timelineController)
        
        // Then state's resolution should win, dropping the choice from pending.
        let deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.roomTaskSummary.isEmpty
        }
        try await deferred.fulfill()
    }
    
    @Test
    func timelineOnlyItemsStillCollectedForOldProtocolRooms() async throws {
        // Given an old-protocol room: no agent state events exist at all, only timeline messages.
        let items: [RoomTimelineItemProtocol] = [
            AgentCanvasStepsRoomTimelineItem(eventID: "task-message", taskID: "task-1", title: "Message title", isResolved: false),
            AgentChoiceRequestRoomTimelineItem(eventID: "choice-1", question: "Deploy?")
        ]
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getStateEventsRawEventTypeClosure = { _ in .success([]) }
        
        // When showing the timeline and enumerating room state (which comes back empty).
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(roomProxy: roomProxy, timelineController: timelineController)
        
        // Then the timeline-only task and pending choice should still be collected.
        let deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.roomTaskSummary.activeTasks.map(\.taskID) == ["task-1"]
                && value.roomTaskSummary.pendingChoices.map(\.eventID) == ["choice-1"]
        }
        try await deferred.fulfill()
    }
    
    // MARK: - Pins
    
    @Test
    func pinnedEvents() async throws {
        let appSettings = AppSettings.volatile()
        
        var configuration = JoinedRoomProxyMockConfiguration(name: "",
                                                             pinnedEventIDs: .init(["test1"]))
        let roomProxyMock = JoinedRoomProxyMock(configuration)
        let infoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(RoomInfoProxyMock(configuration))
        roomProxyMock.infoPublisher = infoSubject.asCurrentValuePublisher()
        
        let viewModel = TimelineViewModel(roomProxy: roomProxyMock,
                                          timelineController: TimelineControllerMock(.init()),
                                          userSession: UserSessionMock(.init()),
                                          mediaPlayerProvider: MediaPlayerProviderMock(),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          appMediator: AppMediatorMock(.init()),
                                          appSettings: appSettings,
                                          analyticsService: AnalyticsServiceMock(.init()),
                                          emojiProvider: EmojiProvider(appSettings: appSettings),
                                          linkMetadataProvider: LinkMetadataProvider(),
                                          timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        #expect(configuration.pinnedEventIDs == viewModel.context.viewState.pinnedEventIDs)
        
        configuration.pinnedEventIDs = ["test1", "test2"]
        let deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.pinnedEventIDs == ["test1", "test2"]
        }
        infoSubject.send(RoomInfoProxyMock(configuration))
        try await deferred.fulfill()
    }
    
    @Test
    func canUserPinEvents() async throws {
        let appSettings = AppSettings.volatile()
        
        let configuration = JoinedRoomProxyMockConfiguration(name: "",
                                                             powerLevelsConfiguration: .init(canUserPin: true))
        let roomProxyMock = JoinedRoomProxyMock(configuration)
        let infoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(RoomInfoProxyMock(configuration))
        roomProxyMock.infoPublisher = infoSubject.asCurrentValuePublisher()
        
        let viewModel = TimelineViewModel(roomProxy: roomProxyMock,
                                          timelineController: TimelineControllerMock(.init()),
                                          userSession: UserSessionMock(.init()),
                                          mediaPlayerProvider: MediaPlayerProviderMock(),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          appMediator: AppMediatorMock(.init()),
                                          appSettings: appSettings,
                                          analyticsService: AnalyticsServiceMock(.init()),
                                          emojiProvider: EmojiProvider(appSettings: appSettings),
                                          linkMetadataProvider: LinkMetadataProvider(),
                                          timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        
        var deferred = deferFulfillment(viewModel.context.$viewState) { value in
            value.canCurrentUserPin
        }
        try await deferred.fulfill()
        
        let powerLevelsProxyMock = RoomPowerLevelsProxyMock(.init())
        powerLevelsProxyMock.canUserPinOrUnpinUserIDReturnValue = .success(false)
        powerLevelsProxyMock.canOwnUserPinOrUnpinReturnValue = false
        roomProxyMock.powerLevelsReturnValue = .success(powerLevelsProxyMock)
        
        let roomInfoProxyMock = RoomInfoProxyMock(configuration)
        roomInfoProxyMock.powerLevels = powerLevelsProxyMock
        
        deferred = deferFulfillment(viewModel.context.$viewState) { value in
            !value.canCurrentUserPin
        }
        infoSubject.send(roomInfoProxyMock)
        try await deferred.fulfill()
    }
    
    // MARK: - Tap Actions
    
    @Test
    func tapSendInfoEncryptionAuthentictyDisplaysAlert() {
        // Given a room with an event whose authenticity could not be verified
        let items = [TextRoomTimelineItem(eventID: "t1", encryptionAuthenticity: .verificationViolation(color: .red))]
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        #expect(viewModel.state.bindings.alertInfo == nil)
        
        viewModel.process(viewAction: .itemSendInfoTapped(itemID: items[0].id))
        
        #expect(viewModel.state.bindings.alertInfo?.title == "Encrypted by a previously-verified user.")
    }
    
    @Test
    func tapSendInfoEncryptionForwarderDisplaysAlert() {
        // Given a room with an event whose key was forwarded
        let items = [TextRoomTimelineItem(eventID: "t1", keyForwarder: .test)]
        let timelineController = TimelineControllerMock(.init(timelineItems: items))
        let viewModel = makeViewModel(timelineController: timelineController)
        
        #expect(viewModel.state.bindings.alertInfo == nil)
        
        viewModel.process(viewAction: .itemSendInfoTapped(itemID: items[0].id))
        
        #expect(viewModel.state.bindings.alertInfo?.title == "alice (@alice:matrix.org) shared this message since you were not in the room when it was sent.")
    }
    
    // MARK: - Helpers
    
    private func makeViewModel(roomProxy: JoinedRoomProxyProtocol? = nil,
                               focussedEventID: String? = nil,
                               timelineController: TimelineControllerProtocol) -> TimelineViewModel {
        let appSettings = AppSettings.volatile()
        
        return TimelineViewModel(roomProxy: roomProxy ?? JoinedRoomProxyMock(.init(name: "")),
                                 focussedEventID: focussedEventID,
                                 timelineController: timelineController,
                                 userSession: UserSessionMock(.init()),
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

private extension TextRoomTimelineItem {
    init(text: String, sender: String, addReactions: Bool = false, addReadReceipts: [ReadReceipt] = []) {
        let reactions = addReactions ? [AggregatedReaction(accountOwnerID: "bob", key: "🦄", senders: [ReactionSender(id: sender, timestamp: Date())])] : []
        self.init(id: .randomEvent,
                  timestamp: .mock,
                  isOutgoing: sender == "bob",
                  isEditable: sender == "bob",
                  canBeRepliedTo: true,
                  sender: .init(id: "@\(sender):server.com", displayName: sender),
                  content: .init(body: text),
                  properties: RoomTimelineItemProperties(reactions: reactions, orderedReadReceipts: addReadReceipts))
    }
}

private extension SeparatorRoomTimelineItem {
    init(uniqueID: TimelineItemIdentifier.UniqueID) {
        self.init(id: .virtual(uniqueID: uniqueID), timestamp: .mock)
    }
}

private extension TextRoomTimelineItem {
    init(eventID: String) {
        self.init(id: .event(uniqueID: .init(UUID().uuidString), eventOrTransactionID: .eventID(eventID)),
                  timestamp: .mock,
                  isOutgoing: false,
                  isEditable: false,
                  canBeRepliedTo: true,
                  sender: .init(id: ""),
                  content: .init(body: "Hello, World!"))
    }
}

private extension TextRoomTimelineItem {
    init(eventID: String, keyForwarder: TimelineItemKeyForwarder) {
        self.init(id: .event(uniqueID: .init(UUID().uuidString), eventOrTransactionID: .eventID(eventID)),
                  timestamp: .mock,
                  isOutgoing: false,
                  isEditable: false,
                  canBeRepliedTo: true,
                  sender: .init(id: ""),
                  content: .init(body: "Hello, World!"),
                  properties: RoomTimelineItemProperties(encryptionForwarder: keyForwarder))
    }
}

private extension TextRoomTimelineItem {
    init(eventID: String, encryptionAuthenticity: EncryptionAuthenticity) {
        self.init(id: .event(uniqueID: .init(UUID().uuidString), eventOrTransactionID: .eventID(eventID)),
                  timestamp: .mock,
                  isOutgoing: false,
                  isEditable: false,
                  canBeRepliedTo: true,
                  sender: .init(id: ""),
                  content: .init(body: "Hello, World!"),
                  properties: RoomTimelineItemProperties(encryptionAuthenticity: encryptionAuthenticity))
    }
}

private extension AgentCanvasStepsRoomTimelineItem {
    init(eventID: String, taskID: String, title: String, isResolved: Bool, steps: [CanvasStep] = []) {
        self.init(id: .event(uniqueID: .init(UUID().uuidString), eventOrTransactionID: .eventID(eventID)),
                  timestamp: .mock,
                  isOutgoing: false,
                  isEditable: false,
                  canBeRepliedTo: true,
                  sender: .init(id: "@agent:server.com"),
                  content: .init(body: title, taskID: taskID, title: title, isResolved: isResolved, steps: steps))
    }
}

private extension AgentChoiceRequestRoomTimelineItem {
    init(eventID: String, question: String, body: String = "fallback body") {
        self.init(id: .event(uniqueID: .init(UUID().uuidString), eventOrTransactionID: .eventID(eventID)),
                  timestamp: .mock,
                  isOutgoing: false,
                  isEditable: false,
                  canBeRepliedTo: true,
                  sender: .init(id: "@agent:server.com"),
                  content: .init(body: body, question: question))
    }
}

private extension TimelineItemSender {
    init(with proxy: RoomMemberProxyMock) {
        self.init(id: proxy.userID,
                  displayName: proxy.displayName ?? "",
                  isDisplayNameAmbiguous: false,
                  avatarURL: proxy.avatarURL)
    }
}

private extension TimelineItemKeyForwarder {
    static var test: TimelineItemKeyForwarder {
        TimelineItemKeyForwarder(id: "@alice:matrix.org", displayName: "alice")
    }
}
