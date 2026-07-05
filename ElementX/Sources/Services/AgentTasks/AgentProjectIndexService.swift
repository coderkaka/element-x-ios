//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

class AgentProjectIndexService: AgentProjectIndexServiceProtocol {
    private let clientProxy: ClientProxyProtocol
    private let roomSummaryProvider: RoomSummaryProviderProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let projectsSubject = CurrentValueSubject<[AgentProjectSummary], Never>([])
    var projectsPublisher: CurrentValuePublisher<[AgentProjectSummary], Never> {
        projectsSubject.asCurrentValuePublisher()
    }
    
    private let pendingChoicesSubject = CurrentValueSubject<[AgentPendingChoiceSummary], Never>([])
    var pendingChoicesPublisher: CurrentValuePublisher<[AgentPendingChoiceSummary], Never> {
        pendingChoicesSubject.asCurrentValuePublisher()
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
        Task { [weak self] in
            guard let self else { return }
            
            var projects = [AgentProjectSummary]()
            var pendingChoices = [AgentPendingChoiceSummary]()
            
            for summary in summaries {
                let goalResult = await clientProxy.getRoomStateEventsRaw(roomID: summary.id, eventType: AgentGoalStateEvent.eventType)
                guard case let .success(goalEvents) = goalResult else {
                    if case let .failure(error) = goalResult {
                        MXLog.error("Skipping room \(summary.id), failed to fetch \(AgentGoalStateEvent.eventType) state events: \(error)")
                    }
                    continue // One bad room must not empty the whole index.
                }
                
                let choiceResult = await clientProxy.getRoomStateEventsRaw(roomID: summary.id, eventType: AgentChoiceStateIndexEvent.eventType)
                guard case let .success(choiceEvents) = choiceResult else {
                    if case let .failure(error) = choiceResult {
                        MXLog.error("Skipping room \(summary.id), failed to fetch \(AgentChoiceStateIndexEvent.eventType) state events: \(error)")
                    }
                    continue
                }
                
                if let goalEvent = goalEvents.compactMap(AgentGoalStateEvent.init(parsingFrom:)).first {
                    projects.append(AgentProjectSummary(roomID: summary.id,
                                                        name: goalEvent.name,
                                                        description: goalEvent.description,
                                                        status: goalEvent.status))
                }
                
                for rawEvent in choiceEvents {
                    guard let choiceEvent = AgentChoiceStateIndexEvent(parsingFrom: rawEvent) else {
                        MXLog.error("Skipping unparseable agent choice state event in room \(summary.id)")
                        continue
                    }
                    guard choiceEvent.isPending else { continue }
                    pendingChoices.append(AgentPendingChoiceSummary(roomID: summary.id,
                                                                    eventID: choiceEvent.eventID,
                                                                    question: choiceEvent.question))
                }
            }
            
            projectsSubject.send(projects.sorted { $0.roomID < $1.roomID })
            pendingChoicesSubject.send(pendingChoices.sorted { $0.roomID < $1.roomID })
        }
    }
}
