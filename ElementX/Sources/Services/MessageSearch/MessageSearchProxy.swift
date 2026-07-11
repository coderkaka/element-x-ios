//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import MatrixRustSDK

final class MessageSearchProxy: MessageSearchProxyProtocol {
    private let searchService: SearchServiceProtocol
    private let eventStringBuilder: RoomEventStringBuilder
    private let userID: String
    
    private let resultsSubject = CurrentValueSubject<[MessageSearchResultItem], Never>([])
    var resultsPublisher: CurrentValuePublisher<[MessageSearchResultItem], Never> {
        resultsSubject.asCurrentValuePublisher()
    }
    
    private var results: [MessageSearchResultItem] {
        get { resultsSubject.value }
        set { resultsSubject.send(newValue) }
    }
    
    private let paginationStateSubject: CurrentValueSubject<MessageSearchPaginationState, Never>
    var paginationStatePublisher: CurrentValuePublisher<MessageSearchPaginationState, Never> {
        paginationStateSubject.asCurrentValuePublisher()
    }
    
    /// Bridge from the SDK's synchronous callback into Swift Concurrency, matching the pattern used by
    /// `RoomDirectorySearchProxy`: a single long-lived `for await` consumer applies updates on the main
    /// actor in FIFO order, guaranteeing one in-flight update at a time.
    private let updatesContinuation: AsyncStream<[SearchServiceResultsUpdate]>.Continuation
    
    private var resultsSubscription: TaskHandle?
    private var paginationStateSubscription: TaskHandle?
    
    deinit {
        updatesContinuation.finish()
    }
    
    init(searchService: SearchServiceProtocol, eventStringBuilder: RoomEventStringBuilder, userID: String) {
        self.searchService = searchService
        self.eventStringBuilder = eventStringBuilder
        self.userID = userID
        
        paginationStateSubject = CurrentValueSubject<MessageSearchPaginationState, Never>(.init(sdkState: searchService.paginationState()))
        
        let (updatesStream, updatesContinuation) = AsyncStream<[SearchServiceResultsUpdate]>.makeStream()
        self.updatesContinuation = updatesContinuation
        
        Task { [weak self] in
            for await updates in updatesStream {
                await self?.updateResultsWithDiffs(updates)
            }
        }
        
        Task {
            resultsSubscription = await searchService.subscribeToResults(listener: SDKListener { updates in
                updatesContinuation.yield(updates)
            })
        }
        
        paginationStateSubscription = searchService.subscribeToPaginationStateUpdates(listener: SDKListener { [weak self] state in
            Task { @MainActor in
                self?.paginationStateSubject.send(.init(sdkState: state))
            }
        })
    }
    
    func search(query: String) async -> Result<Void, MessageSearchError> {
        do {
            try await searchService.setQuery(query: query)
            return .success(())
        } catch {
            MXLog.error("Failed searching messages with error: \(error)")
            return .failure(.searchFailed)
        }
    }
    
    func paginate() async -> Result<Void, MessageSearchError> {
        do {
            try await searchService.paginate()
            return .success(())
        } catch {
            MXLog.error("Failed paginating message search with error: \(error)")
            return .failure(.paginationFailed)
        }
    }
    
    // MARK: - Private
    
    private func updateResultsWithDiffs(_ updates: [SearchServiceResultsUpdate]) async {
        // Building the results and applying the CollectionDifference can be expensive for large
        // search batches, so compute off the main actor and only hop back to publish.
        results = await Self.updatedResults(from: updates, on: results, eventStringBuilder: eventStringBuilder, userID: userID)
    }
    
    @concurrent
    private static func updatedResults(from updates: [SearchServiceResultsUpdate],
                                       on currentResults: [MessageSearchResultItem],
                                       eventStringBuilder: RoomEventStringBuilder,
                                       userID: String) async -> [MessageSearchResultItem] {
        updates.reduce(currentResults) { currentItems, diff in
            processDiff(diff, on: currentItems, eventStringBuilder: eventStringBuilder, userID: userID)
        }
    }
    
    private nonisolated static func processDiff(_ diff: SearchServiceResultsUpdate,
                                                on currentItems: [MessageSearchResultItem],
                                                eventStringBuilder: RoomEventStringBuilder,
                                                userID: String) -> [MessageSearchResultItem] {
        guard let collectionDiff = buildDiff(from: diff, on: currentItems, eventStringBuilder: eventStringBuilder, userID: userID) else {
            return currentItems
        }
        
        guard let updatedItems = currentItems.applying(collectionDiff) else {
            return currentItems
        }
        
        return updatedItems
    }
    
    private nonisolated static func buildDiff(from diff: SearchServiceResultsUpdate,
                                              on currentItems: [MessageSearchResultItem],
                                              eventStringBuilder: RoomEventStringBuilder,
                                              userID: String) -> CollectionDifference<MessageSearchResultItem>? {
        var changes = [CollectionDifference<MessageSearchResultItem>.Change]()
        
        func item(for result: SearchServiceResult) -> MessageSearchResultItem {
            buildResult(for: result, eventStringBuilder: eventStringBuilder, userID: userID)
        }
        
        switch diff {
        case .append(let values):
            for (index, value) in values.enumerated() {
                changes.append(.insert(offset: currentItems.count + index, element: item(for: value), associatedWith: nil))
            }
        case .clear:
            for (index, value) in currentItems.enumerated() {
                changes.append(.remove(offset: index, element: value, associatedWith: nil))
            }
        case .insert(let index, let value):
            changes.append(.insert(offset: Int(index), element: item(for: value), associatedWith: nil))
        case .popBack:
            guard let value = currentItems.last else {
                fatalError()
            }
            
            changes.append(.remove(offset: currentItems.count - 1, element: value, associatedWith: nil))
        case .popFront:
            let result = currentItems[0]
            changes.append(.remove(offset: 0, element: result, associatedWith: nil))
        case .pushBack(let value):
            changes.append(.insert(offset: currentItems.count, element: item(for: value), associatedWith: nil))
        case .pushFront(let value):
            changes.append(.insert(offset: 0, element: item(for: value), associatedWith: nil))
        case .remove(let index):
            let result = currentItems[Int(index)]
            changes.append(.remove(offset: Int(index), element: result, associatedWith: nil))
        case .reset(let values):
            for (index, result) in currentItems.enumerated() {
                changes.append(.remove(offset: index, element: result, associatedWith: nil))
            }
            
            for (index, value) in values.enumerated() {
                changes.append(.insert(offset: index, element: item(for: value), associatedWith: nil))
            }
        case .set(let index, let value):
            let result = item(for: value)
            changes.append(.remove(offset: Int(index), element: result, associatedWith: nil))
            changes.append(.insert(offset: Int(index), element: result, associatedWith: nil))
        case .truncate(let length):
            for (index, value) in currentItems.enumerated() {
                if index < length {
                    continue
                }
                
                changes.append(.remove(offset: index, element: value, associatedWith: nil))
            }
        }
        
        return CollectionDifference(changes)
    }
    
    private nonisolated static func buildResult(for result: SearchServiceResult,
                                                eventStringBuilder: RoomEventStringBuilder,
                                                userID: String) -> MessageSearchResultItem {
        switch result {
        case .message(let roomID, let message):
            let sender = TimelineItemSender(senderID: message.sender, senderProfile: message.senderProfile)
            let body = eventStringBuilder.buildAttributedString(for: message.content, sender: sender, isOutgoing: message.sender == userID)
            
            return MessageSearchResultItem(eventID: message.eventId,
                                           roomID: roomID,
                                           sender: sender,
                                           body: body,
                                           timestamp: Date(timeIntervalSince1970: TimeInterval(message.timestamp / 1000)))
        }
    }
}

private extension MessageSearchPaginationState {
    init(sdkState: MatrixRustSDK.SearchServicePaginationState) {
        switch sdkState {
        case .loading:
            self = .loading
        case .idle(let endReached):
            self = .idle(endReached: endReached)
        }
    }
}
