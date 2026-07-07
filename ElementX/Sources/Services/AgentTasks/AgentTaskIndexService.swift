//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

class AgentTaskIndexService: AgentTaskIndexServiceProtocol {
    private let clientProxy: ClientProxyProtocol
    private let roomSummaryProvider: RoomSummaryProviderProtocol
    private var cancellables = Set<AnyCancellable>()
    /// Cancelled and replaced on every rebuild so a slower, earlier-triggered rebuild can never
    /// overwrite a newer one's result with stale data.
    private var rebuildTask: Task<Void, Never>?
    
    private let tasksSubject = CurrentValueSubject<[AgentTaskSummary], Never>([])
    var tasksPublisher: CurrentValuePublisher<[AgentTaskSummary], Never> {
        tasksSubject.asCurrentValuePublisher()
    }
    
    init(clientProxy: ClientProxyProtocol, roomSummaryProvider: RoomSummaryProviderProtocol) {
        self.clientProxy = clientProxy
        self.roomSummaryProvider = roomSummaryProvider
    }
    
    func start() {
        roomSummaryProvider.roomListPublisher
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] summaries in
                self?.rebuildIndex(from: summaries)
            }
            .store(in: &cancellables)
    }
    
    private func rebuildIndex(from summaries: [RoomSummary]) {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            guard let self else { return }
            
            var tasks = [AgentTaskSummary]()
            for summary in summaries {
                guard !Task.isCancelled else { return }
                
                guard case let .success(rawEvents) = await clientProxy.getRoomStateEventsRaw(roomID: summary.id,
                                                                                             eventType: AgentTaskStateEvent.eventType) else {
                    continue // One bad room must not empty the whole index.
                }
                
                for rawEvent in rawEvents {
                    guard let stateEvent = AgentTaskStateEvent(parsingFrom: rawEvent) else {
                        MXLog.error("Skipping unparseable agent task state event in room \(summary.id)")
                        continue
                    }
                    tasks.append(AgentTaskSummary(roomID: summary.id,
                                                  roomName: summary.name,
                                                  taskID: stateEvent.taskID,
                                                  title: stateEvent.title,
                                                  isResolved: stateEvent.isResolved,
                                                  doneStepCount: stateEvent.doneStepCount,
                                                  totalStepCount: stateEvent.totalStepCount,
                                                  metric: stateEvent.metric))
                }
            }
            
            guard !Task.isCancelled else { return }
            
            let unresolved = tasks.filter { !$0.isResolved }
            let resolved = tasks.filter(\.isResolved)
            tasksSubject.send(unresolved + resolved)
        }
    }
    
    func metricHistory(roomID: String, taskID: String, limit: UInt32) async -> [AgentTaskMetricHistoryPoint] {
        guard case let .success(rawEvents) = await clientProxy.getRoomStateEventHistoryRaw(roomID: roomID,
                                                                                           eventType: AgentTaskStateEvent.eventType,
                                                                                           stateKey: taskID,
                                                                                           limit: limit) else {
            return []
        }
        
        return rawEvents.compactMap(AgentTaskMetricHistoryPoint.init(parsingFrom:)).sorted { $0.date < $1.date }
    }
}
