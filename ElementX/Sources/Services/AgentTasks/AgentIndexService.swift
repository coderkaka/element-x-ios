//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

/// Indexes 差事(tasks)/案(projects)/请旨(pending choices)/标的(objectives) across every joined
/// room in one pass — merged from what used to be two near-identical services, each
/// independently doing the same "debounce room list → fetch state per room → parse → publish"
/// dance for a different state event type.
class AgentIndexService: AgentIndexServiceProtocol {
    private let clientProxy: ClientProxyProtocol
    /// `staticRoomSummaryProvider`, not the main tab's `roomSummaryProvider` — the index must
    /// stay full regardless of whatever search/未读 filtering 政事堂 has applied to the main
    /// provider, since the 差事 tab's own 道 filter (applied in `AgentTasksScreenViewModel`) is
    /// the only filtering this index should ever be subject to.
    private let roomSummaryProvider: StaticRoomSummaryProviderProtocol
    private var cancellables = Set<AnyCancellable>()
    /// Cancelled and replaced on every rebuild so a slower, earlier-triggered rebuild can never
    /// overwrite a newer one's result with stale data.
    private var rebuildTask: Task<Void, Never>?
    
    private let tasksSubject = CurrentValueSubject<[AgentTaskSummary], Never>([])
    var tasksPublisher: CurrentValuePublisher<[AgentTaskSummary], Never> {
        tasksSubject.asCurrentValuePublisher()
    }
    
    private let projectsSubject = CurrentValueSubject<[AgentProjectSummary], Never>([])
    var projectsPublisher: CurrentValuePublisher<[AgentProjectSummary], Never> {
        projectsSubject.asCurrentValuePublisher()
    }
    
    private let pendingChoicesSubject = CurrentValueSubject<[AgentPendingChoiceSummary], Never>([])
    var pendingChoicesPublisher: CurrentValuePublisher<[AgentPendingChoiceSummary], Never> {
        pendingChoicesSubject.asCurrentValuePublisher()
    }
    
    private let objectivesSubject = CurrentValueSubject<[AgentObjectiveSummary], Never>([])
    var objectivesPublisher: CurrentValuePublisher<[AgentObjectiveSummary], Never> {
        objectivesSubject.asCurrentValuePublisher()
    }
    
    init(clientProxy: ClientProxyProtocol, roomSummaryProvider: StaticRoomSummaryProviderProtocol) {
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
            var projects = [AgentProjectSummary]()
            var pendingChoices = [AgentPendingChoiceSummary]()
            var objectives = [AgentObjectiveSummary]()
            
            for summary in summaries {
                guard !Task.isCancelled else { return }
                
                // The 4 event types are fetched and handled independently — one type failing
                // for a room must not hide data this room already has for the others.
                let taskEventsResult = await clientProxy.getRoomStateEventsRaw(roomID: summary.id, eventType: AgentTaskStateEvent.eventType)
                let goalEventsResult = await clientProxy.getRoomStateEventsRaw(roomID: summary.id, eventType: AgentGoalStateEvent.eventType)
                let choiceEventsResult = await clientProxy.getRoomStateEventsRaw(roomID: summary.id, eventType: AgentChoiceStateIndexEvent.eventType)
                let objectiveEventsResult = await clientProxy.getRoomStateEventsRaw(roomID: summary.id, eventType: AgentObjectiveStateEvent.eventType)
                
                switch taskEventsResult {
                case .success(let rawEvents):
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
                                                      metric: stateEvent.metric,
                                                      objectiveID: stateEvent.objectiveID))
                    }
                case .failure(let error):
                    MXLog.error("Skipping room \(summary.id) tasks, failed to fetch \(AgentTaskStateEvent.eventType) state events: \(error)")
                }
                
                switch goalEventsResult {
                case .success(let goalEvents):
                    if let goalEvent = goalEvents.compactMap(AgentGoalStateEvent.init(parsingFrom:)).first {
                        projects.append(AgentProjectSummary(roomID: summary.id,
                                                            name: goalEvent.name,
                                                            description: goalEvent.description,
                                                            status: goalEvent.status))
                    }
                case .failure(let error):
                    MXLog.error("Skipping room \(summary.id) project, failed to fetch \(AgentGoalStateEvent.eventType) state events: \(error)")
                }
                
                switch choiceEventsResult {
                case .success(let choiceEvents):
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
                case .failure(let error):
                    MXLog.error("Skipping room \(summary.id) pending choices, failed to fetch \(AgentChoiceStateIndexEvent.eventType) state events: \(error)")
                }
                
                switch objectiveEventsResult {
                case .success(let objectiveEvents):
                    for rawEvent in objectiveEvents {
                        guard let objectiveEvent = AgentObjectiveStateEvent(parsingFrom: rawEvent) else {
                            MXLog.error("Skipping unparseable agent objective state event in room \(summary.id)")
                            continue
                        }
                        objectives.append(AgentObjectiveSummary(roomID: summary.id,
                                                                objectiveID: objectiveEvent.objectiveID,
                                                                title: objectiveEvent.title,
                                                                status: objectiveEvent.status,
                                                                successMetrics: objectiveEvent.successMetrics,
                                                                exitOptions: objectiveEvent.exitOptions,
                                                                priority: objectiveEvent.priority,
                                                                updatedAt: objectiveEvent.updatedAt))
                    }
                case .failure(let error):
                    MXLog.error("Skipping room \(summary.id) objectives, failed to fetch \(AgentObjectiveStateEvent.eventType) state events: \(error)")
                }
            }
            
            guard !Task.isCancelled else { return }
            
            let unresolvedTasks = tasks.filter { !$0.isResolved }
            let resolvedTasks = tasks.filter(\.isResolved)
            tasksSubject.send(unresolvedTasks + resolvedTasks)
            projectsSubject.send(projects.sorted { $0.roomID < $1.roomID })
            pendingChoicesSubject.send(pendingChoices.sorted { $0.roomID < $1.roomID })
            objectivesSubject.send(objectives.sorted { $0.roomID < $1.roomID })
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
