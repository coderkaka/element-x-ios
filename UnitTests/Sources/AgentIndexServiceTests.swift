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
import Testing

@MainActor
struct AgentIndexServiceTests {
    // MARK: - Task parsing
    
    @Test
    func taskStateEventParsing() {
        let json = """
        {"type":"io.element.agent.canvas.steps","state_key":"task-1","sender":"@agent:example.com","content":\
        {"title":"Refactor the parser","status":"in_progress","steps":[\
        {"id":"s1","label":"Read code","status":"done"},\
        {"id":"s2","label":"Write tests","status":"in_progress"},\
        {"id":"s3","label":"Ship","status":"pending"}]}}
        """
        
        let event = AgentTaskStateEvent(parsingFrom: json)
        
        #expect(event?.taskID == "task-1")
        #expect(event?.title == "Refactor the parser")
        #expect(event?.isResolved == false)
        #expect(event?.doneStepCount == 1)
        #expect(event?.totalStepCount == 3)
    }
    
    @Test
    func taskStateEventParsingWithMissingTitleAndSteps() {
        let json = """
        {"type":"io.element.agent.canvas.steps","state_key":"task-2","content":{"status":"done"}}
        """
        
        let event = AgentTaskStateEvent(parsingFrom: json)
        
        #expect(event?.taskID == "task-2")
        #expect(event?.title == nil)
        #expect(event?.isResolved == true)
        #expect(event?.doneStepCount == 0)
        #expect(event?.totalStepCount == 0)
    }
    
    @Test
    func taskStateEventParsingFailures() {
        #expect(AgentTaskStateEvent(parsingFrom: "not json at all") == nil)
        #expect(AgentTaskStateEvent(parsingFrom: #"{"state_key":"task-3"}"#) == nil)
        #expect(AgentTaskStateEvent(parsingFrom: #"{"content":{"status":"done"}}"#) == nil)
    }
    
    // MARK: - Goal parsing
    
    @Test
    func goalStateEventParsingFull() {
        let json = """
        {"type":"io.element.agent.goal","state_key":"","sender":"@agent:example.com","content":\
        {"name":"Ship the launch","description":"Coordinate the v2 launch","status":"active"}}
        """
        
        let event = AgentGoalStateEvent(parsingFrom: json)
        
        #expect(event?.name == "Ship the launch")
        #expect(event?.description == "Coordinate the v2 launch")
        #expect(event?.status == .active)
    }
    
    @Test
    func goalStateEventParsingMinimalContentDefaultsToActive() {
        let json = """
        {"type":"io.element.agent.goal","state_key":"","content":{}}
        """
        
        let event = AgentGoalStateEvent(parsingFrom: json)
        
        #expect(event?.name == nil)
        #expect(event?.description == nil)
        #expect(event?.status == .active)
    }
    
    @Test
    func goalStateEventParsingMissingStatusDefaultsToActive() {
        let json = """
        {"type":"io.element.agent.goal","state_key":"","content":{"name":"No status"}}
        """
        
        let event = AgentGoalStateEvent(parsingFrom: json)
        
        #expect(event?.name == "No status")
        #expect(event?.status == .active)
    }
    
    @Test
    func goalStateEventParsingUnknownStatusDefaultsToActive() {
        let json = """
        {"type":"io.element.agent.goal","state_key":"","content":{"status":"some_future_status"}}
        """
        
        let event = AgentGoalStateEvent(parsingFrom: json)
        
        #expect(event?.status == .active)
    }
    
    @Test
    func goalStateEventParsingEachKnownStatus() {
        func status(for rawStatus: String) -> AgentProjectStatus? {
            let json = """
            {"type":"io.element.agent.goal","state_key":"","content":{"status":"\(rawStatus)"}}
            """
            return AgentGoalStateEvent(parsingFrom: json)?.status
        }
        
        #expect(status(for: "active") == .active)
        #expect(status(for: "done") == .done)
        #expect(status(for: "archived") == .archived)
    }
    
    @Test
    func goalStateEventParsingFailures() {
        #expect(AgentGoalStateEvent(parsingFrom: "not json at all") == nil)
        #expect(AgentGoalStateEvent(parsingFrom: "42") == nil)
        #expect(AgentGoalStateEvent(parsingFrom: "[]") == nil)
    }
    
    // MARK: - Choice parsing
    
    @Test
    func choiceStateEventParsingPendingWithNoResolvedSelection() {
        let json = """
        {"type":"io.element.agent.choice_request","state_key":"$original-event-id","content":\
        {"status":"pending","question":"Which approach?"}}
        """
        
        let event = AgentChoiceStateIndexEvent(parsingFrom: json)
        
        #expect(event?.eventID == "$original-event-id")
        #expect(event?.question == "Which approach?")
        #expect(event?.isPending == true)
    }
    
    @Test
    func choiceStateEventParsingResolvedWithNonEmptySelection() {
        let json = """
        {"type":"io.element.agent.choice_request","state_key":"$original-event-id","content":\
        {"status":"resolved","question":"Which approach?","resolved_selection":["option-a"]}}
        """
        
        let event = AgentChoiceStateIndexEvent(parsingFrom: json)
        
        #expect(event?.isPending == false)
    }
    
    @Test
    func choiceStateEventParsingPendingWithExplicitStatusAndEmptySelection() {
        let json = """
        {"type":"io.element.agent.choice_request","state_key":"$original-event-id","content":\
        {"status":"pending","question":"Which approach?","resolved_selection":[]}}
        """
        
        let event = AgentChoiceStateIndexEvent(parsingFrom: json)
        
        #expect(event?.isPending == true)
    }
    
    @Test
    func choiceStateEventQuestionPassthrough() {
        let json = """
        {"type":"io.element.agent.choice_request","state_key":"$original-event-id","content":\
        {"question":"Pick one of the options below"}}
        """
        
        let event = AgentChoiceStateIndexEvent(parsingFrom: json)
        
        #expect(event?.question == "Pick one of the options below")
        #expect(event?.isPending == true)
    }
    
    @Test
    func choiceStateEventParsingCancelledWithNoResolvedSelectionIsNotPending() {
        // 请旨撤销: a cancelled request is never pending, even with an empty/missing selection.
        let json = """
        {"type":"io.element.agent.choice_request","state_key":"$original-event-id","content":\
        {"status":"cancelled","question":"Which approach?"}}
        """
        
        let event = AgentChoiceStateIndexEvent(parsingFrom: json)
        
        #expect(event?.isPending == false)
    }
    
    @Test
    func choiceStateEventParsingCancelledWithNonEmptySelectionIsNotPending() {
        // Resolved wins even alongside a cancelled status — either way it's not pending.
        let json = """
        {"type":"io.element.agent.choice_request","state_key":"$original-event-id","content":\
        {"status":"cancelled","question":"Which approach?","resolved_selection":["option-a"]}}
        """
        
        let event = AgentChoiceStateIndexEvent(parsingFrom: json)
        
        #expect(event?.isPending == false)
    }
    
    @Test
    func choiceStateEventParsingFailures() {
        #expect(AgentChoiceStateIndexEvent(parsingFrom: "not json at all") == nil)
        #expect(AgentChoiceStateIndexEvent(parsingFrom: #"{"content":{"status":"pending"}}"#) == nil)
        #expect(AgentChoiceStateIndexEvent(parsingFrom: #"{"state_key":"$abc"}"#) == nil)
    }
    
    // MARK: - Objective parsing
    
    @Test
    func objectiveStateEventParsingFull() {
        let json = """
        {"type":"io.element.agent.objective","state_key":"obj-1","content":\
        {"title":"验证指标趋势图","status":"active",\
        "success_metrics":["真机上看到真实历史点"],"exit_options":["直接发布","放弃"],\
        "priority":1,"updated_at":1751900000000}}
        """
        
        let event = AgentObjectiveStateEvent(parsingFrom: json)
        
        #expect(event?.objectiveID == "obj-1")
        #expect(event?.title == "验证指标趋势图")
        #expect(event?.status == .active)
        #expect(event?.successMetrics == ["真机上看到真实历史点"])
        #expect(event?.exitOptions == ["直接发布", "放弃"])
        #expect(event?.priority == 1)
        #expect(event?.updatedAt == Date(timeIntervalSince1970: 1_751_900_000))
    }
    
    @Test
    func objectiveStateEventParsingMinimalContentDefaults() {
        let json = """
        {"type":"io.element.agent.objective","state_key":"obj-2","content":{}}
        """
        
        let event = AgentObjectiveStateEvent(parsingFrom: json)
        
        #expect(event?.title == "obj-2")
        #expect(event?.status == .active)
        #expect(event?.successMetrics == [])
        #expect(event?.exitOptions == [])
        #expect(event?.priority == 0)
    }
    
    @Test
    func objectiveStateEventParsingEachKnownStatus() {
        func status(for rawStatus: String) -> AgentObjectiveStatus? {
            let json = """
            {"type":"io.element.agent.objective","state_key":"obj-3","content":{"status":"\(rawStatus)"}}
            """
            return AgentObjectiveStateEvent(parsingFrom: json)?.status
        }
        
        #expect(status(for: "active") == .active)
        #expect(status(for: "done") == .done)
        #expect(status(for: "abandoned") == .abandoned)
        #expect(status(for: "some_future_status") == .active)
    }
    
    @Test
    func objectiveStateEventParsingFailures() {
        #expect(AgentObjectiveStateEvent(parsingFrom: "not json at all") == nil)
        #expect(AgentObjectiveStateEvent(parsingFrom: #"{"content":{"status":"active"}}"#) == nil)
    }
    
    // MARK: - Task indexing
    
    @Test
    func unresolvedTasksAreListedBeforeResolvedOnes() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A"),
                                          .mock(id: "!b:example.com", name: "Room B")],
                                  taskEvents: { roomID in
                                      switch roomID {
                                      case "!a:example.com":
                                          .success([Self.resolvedTaskEventJSON])
                                      default:
                                          .success([Self.unresolvedTaskEventJSON])
                                      }
                                  })
        
        let deferred = deferFulfillment(service.tasksPublisher) { !$0.isEmpty }
        service.start()
        let tasks = try await deferred.fulfill()
        
        #expect(tasks.map(\.taskID) == ["task-unresolved", "task-resolved"])
        #expect(tasks[0].roomName == "Room B")
        #expect(tasks[0].isResolved == false)
        #expect(tasks[0].title == "Unresolved task")
        #expect(tasks[0].doneStepCount == 1)
        #expect(tasks[0].totalStepCount == 2)
        #expect(tasks[1].roomName == "Room A")
        #expect(tasks[1].isResolved == true)
    }
    
    @Test
    func taskFetchFailureIsSkippedWhileOtherRoomsStillIndex() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A"),
                                          .mock(id: "!b:example.com", name: "Room B")],
                                  taskEvents: { roomID in
                                      switch roomID {
                                      case "!a:example.com":
                                          .failure(.sdkError(ClientProxyMockError.generic))
                                      default:
                                          .success([Self.unresolvedTaskEventJSON])
                                      }
                                  })
        
        let deferred = deferFulfillment(service.tasksPublisher) { !$0.isEmpty }
        service.start()
        let tasks = try await deferred.fulfill()
        
        #expect(tasks.count == 1)
        #expect(tasks[0].roomID == "!b:example.com")
        #expect(tasks[0].taskID == "task-unresolved")
    }
    
    @Test
    func unparseableTaskEventIsSkipped() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A")],
                                  taskEvents: { _ in .success(["not json at all", Self.unresolvedTaskEventJSON]) })
        
        let deferred = deferFulfillment(service.tasksPublisher) { !$0.isEmpty }
        service.start()
        let tasks = try await deferred.fulfill()
        
        #expect(tasks.count == 1)
        #expect(tasks[0].taskID == "task-unresolved")
    }
    
    @Test
    func taskObjectiveIDIsParsedWhenPresent() async throws {
        let json = """
        {"type":"io.element.agent.canvas.steps","state_key":"task-with-objective","content":\
        {"status":"in_progress","objective_id":"obj-1"}}
        """
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A")],
                                  taskEvents: { _ in .success([json]) })
        
        let deferred = deferFulfillment(service.tasksPublisher) { !$0.isEmpty }
        service.start()
        let tasks = try await deferred.fulfill()
        
        #expect(tasks[0].objectiveID == "obj-1")
    }
    
    @Test
    func taskWithoutObjectiveIDParsesToNil() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A")],
                                  taskEvents: { _ in .success([Self.unresolvedTaskEventJSON]) })
        
        let deferred = deferFulfillment(service.tasksPublisher) { !$0.isEmpty }
        service.start()
        let tasks = try await deferred.fulfill()
        
        #expect(tasks[0].objectiveID == nil)
    }
    
    // MARK: - Project/pending-choice indexing
    
    @Test
    func projectsAreIndexedFromGoalEvents() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A"),
                                          .mock(id: "!b:example.com", name: "Room B")],
                                  goalEvents: { roomID in
                                      switch roomID {
                                      case "!a:example.com":
                                          .success([Self.goalEventJSON(name: "Project A", status: "active")])
                                      default:
                                          .success([Self.goalEventJSON(name: "Project B", status: "done")])
                                      }
                                  })
        
        let deferred = deferFulfillment(service.projectsPublisher) { !$0.isEmpty }
        service.start()
        let projects = try await deferred.fulfill()
        
        #expect(projects.map(\.roomID) == ["!a:example.com", "!b:example.com"])
        #expect(projects[0].name == "Project A")
        #expect(projects[0].status == .active)
        #expect(projects[1].name == "Project B")
        #expect(projects[1].status == .done)
    }
    
    @Test
    func pendingChoicesAreIndexedAndResolvedOnesAreExcluded() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A"),
                                          .mock(id: "!b:example.com", name: "Room B")],
                                  choiceEvents: { roomID in
                                      switch roomID {
                                      case "!a:example.com":
                                          .success([Self.choiceEventJSON(stateKey: "$pending-event", status: "pending", resolvedSelection: nil)])
                                      default:
                                          .success([Self.choiceEventJSON(stateKey: "$resolved-event", status: "resolved", resolvedSelection: ["option-a"])])
                                      }
                                  })
        
        let deferred = deferFulfillment(service.pendingChoicesPublisher) { !$0.isEmpty }
        service.start()
        let pendingChoices = try await deferred.fulfill()
        
        #expect(pendingChoices.count == 1)
        #expect(pendingChoices[0].roomID == "!a:example.com")
        #expect(pendingChoices[0].eventID == "$pending-event")
    }
    
    @Test
    func cancelledChoicesAreExcludedFromPending() async throws {
        // 请旨撤销: a cancelled choice request must not surface in the cross-room pending index.
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A"),
                                          .mock(id: "!b:example.com", name: "Room B")],
                                  choiceEvents: { roomID in
                                      switch roomID {
                                      case "!a:example.com":
                                          .success([Self.choiceEventJSON(stateKey: "$pending-event", status: "pending", resolvedSelection: nil)])
                                      default:
                                          .success([Self.choiceEventJSON(stateKey: "$cancelled-event", status: "cancelled", resolvedSelection: nil)])
                                      }
                                  })
        
        let deferred = deferFulfillment(service.pendingChoicesPublisher) { !$0.isEmpty }
        service.start()
        let pendingChoices = try await deferred.fulfill()
        
        #expect(pendingChoices.count == 1)
        #expect(pendingChoices[0].roomID == "!a:example.com")
        #expect(pendingChoices[0].eventID == "$pending-event")
    }
    
    @Test
    func objectivesAreIndexedFromObjectiveEvents() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A"),
                                          .mock(id: "!b:example.com", name: "Room B")],
                                  objectiveEvents: { roomID in
                                      switch roomID {
                                      case "!a:example.com":
                                          .success([Self.objectiveEventJSON(objectiveID: "obj-1", title: "Objective A", status: "active")])
                                      default:
                                          .success([Self.objectiveEventJSON(objectiveID: "obj-2", title: "Objective B", status: "done")])
                                      }
                                  })
        
        let deferred = deferFulfillment(service.objectivesPublisher) { !$0.isEmpty }
        service.start()
        let objectives = try await deferred.fulfill()
        
        #expect(objectives.map(\.roomID) == ["!a:example.com", "!b:example.com"])
        #expect(objectives[0].title == "Objective A")
        #expect(objectives[0].status == .active)
        #expect(objectives[1].title == "Objective B")
        #expect(objectives[1].status == .done)
    }
    
    // MARK: - Cross-category independence
    
    //
    // Tasks/projects/pending-choices are fetched concurrently and handled independently per
    // room — one category failing for a room must never hide that room's data in another
    // category. (An earlier version coupled goal+choice fetches sequentially, so a choice
    // fetch failure silently dropped an already-fetched goal too; that coupling was removed
    // when the two index services this file used to test were merged into one.)
    
    @Test
    func goalFetchFailureDoesNotAffectThatRoomsPendingChoices() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A"),
                                          .mock(id: "!b:example.com", name: "Room B")],
                                  goalEvents: { roomID in
                                      switch roomID {
                                      case "!a:example.com":
                                          .failure(.sdkError(ClientProxyMockError.generic))
                                      default:
                                          .success([Self.goalEventJSON(name: "Project B", status: "active")])
                                      }
                                  },
                                  choiceEvents: { _ in .success([Self.choiceEventJSON(stateKey: "$pending-event", status: "pending", resolvedSelection: nil)]) })
        
        let deferred = deferFulfillment(service.projectsPublisher) { !$0.isEmpty }
        service.start()
        let projects = try await deferred.fulfill()
        
        #expect(projects.count == 1)
        #expect(projects[0].roomID == "!b:example.com")
        
        let pendingChoices = service.pendingChoicesPublisher.value
        #expect(pendingChoices.count == 2)
        #expect(pendingChoices.map(\.roomID).sorted() == ["!a:example.com", "!b:example.com"])
    }
    
    @Test
    func choiceFetchFailureDoesNotAffectThatRoomsProject() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A"),
                                          .mock(id: "!b:example.com", name: "Room B")],
                                  goalEvents: { _ in .success([Self.goalEventJSON(name: "Project", status: "active")]) },
                                  choiceEvents: { roomID in
                                      switch roomID {
                                      case "!a:example.com":
                                          .failure(.sdkError(ClientProxyMockError.generic))
                                      default:
                                          .success([])
                                      }
                                  })
        
        let deferred = deferFulfillment(service.projectsPublisher) { $0.count == 2 }
        service.start()
        let projects = try await deferred.fulfill()
        
        #expect(projects.map(\.roomID).sorted() == ["!a:example.com", "!b:example.com"])
    }
    
    @Test
    func taskFetchFailureDoesNotAffectThatRoomsProjectOrPendingChoices() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A")],
                                  taskEvents: { _ in .failure(.sdkError(ClientProxyMockError.generic)) },
                                  goalEvents: { _ in .success([Self.goalEventJSON(name: "Project A", status: "active")]) },
                                  choiceEvents: { _ in .success([Self.choiceEventJSON(stateKey: "$pending-event", status: "pending", resolvedSelection: nil)]) })
        
        let deferred = deferFulfillment(service.projectsPublisher) { !$0.isEmpty }
        service.start()
        let projects = try await deferred.fulfill()
        
        #expect(projects.count == 1)
        #expect(service.tasksPublisher.value.isEmpty)
        #expect(service.pendingChoicesPublisher.value.count == 1)
    }
    
    // MARK: - Helpers
    
    private static let unresolvedTaskEventJSON = """
    {"type":"io.element.agent.canvas.steps","state_key":"task-unresolved","content":\
    {"title":"Unresolved task","status":"in_progress","steps":[\
    {"id":"s1","label":"First","status":"done"},\
    {"id":"s2","label":"Second","status":"pending"}]}}
    """
    
    private static let resolvedTaskEventJSON = """
    {"type":"io.element.agent.canvas.steps","state_key":"task-resolved","content":\
    {"title":"Resolved task","status":"done","steps":[{"id":"s1","label":"First","status":"done"}]}}
    """
    
    private static func goalEventJSON(name: String, status: String) -> String {
        """
        {"type":"io.element.agent.goal","state_key":"","content":{"name":"\(name)","status":"\(status)"}}
        """
    }
    
    private static func choiceEventJSON(stateKey: String, status: String, resolvedSelection: [String]?) -> String {
        let resolvedSelectionField: String
        if let resolvedSelection {
            let itemsJSON = resolvedSelection.map { "\"\($0)\"" }.joined(separator: ",")
            resolvedSelectionField = "\"resolved_selection\":[\(itemsJSON)],"
        } else {
            resolvedSelectionField = ""
        }
        return """
        {"type":"io.element.agent.choice_request","state_key":"\(stateKey)","content":\
        {\(resolvedSelectionField)"status":"\(status)","question":"Which approach?"}}
        """
    }
    
    private static func objectiveEventJSON(objectiveID: String, title: String, status: String) -> String {
        """
        {"type":"io.element.agent.objective","state_key":"\(objectiveID)","content":{"title":"\(title)","status":"\(status)"}}
        """
    }
    
    private func makeService(rooms: [RoomSummary],
                             taskEvents: @escaping (String) -> Result<[String], ClientProxyError> = { _ in .success([]) },
                             goalEvents: @escaping (String) -> Result<[String], ClientProxyError> = { _ in .success([]) },
                             choiceEvents: @escaping (String) -> Result<[String], ClientProxyError> = { _ in .success([]) },
                             objectiveEvents: @escaping (String) -> Result<[String], ClientProxyError> = { _ in .success([]) }) -> AgentIndexServiceProtocol {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.getRoomStateEventsRawRoomIDEventTypeClosure = { roomID, eventType in
            switch eventType {
            case AgentTaskStateEvent.eventType:
                taskEvents(roomID)
            case AgentGoalStateEvent.eventType:
                goalEvents(roomID)
            case AgentObjectiveStateEvent.eventType:
                objectiveEvents(roomID)
            default:
                choiceEvents(roomID)
            }
        }
        
        let roomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded(rooms)))
        
        return AgentIndexService(clientProxy: clientProxy, roomSummaryProvider: roomSummaryProvider)
    }
}
