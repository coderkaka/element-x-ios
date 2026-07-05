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
struct AgentProjectIndexServiceTests {
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
    func choiceStateEventParsingFailures() {
        #expect(AgentChoiceStateIndexEvent(parsingFrom: "not json at all") == nil)
        #expect(AgentChoiceStateIndexEvent(parsingFrom: #"{"content":{"status":"pending"}}"#) == nil)
        #expect(AgentChoiceStateIndexEvent(parsingFrom: #"{"state_key":"$abc"}"#) == nil)
    }

    // MARK: - Indexing

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
                                   },
                                   choiceEvents: { _ in .success([]) })

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
                                   goalEvents: { _ in .success([]) },
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
    func failingRoomIsSkippedForBothPublishersWhileOthersStillIndex() async throws {
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
        #expect(pendingChoices.count == 1)
        #expect(pendingChoices[0].roomID == "!b:example.com")
    }

    @Test
    func choiceFetchFailureAlsoSkipsProjectsForThatRoom() async throws {
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

        let deferred = deferFulfillment(service.projectsPublisher) { !$0.isEmpty }
        service.start()
        let projects = try await deferred.fulfill()

        #expect(projects.count == 1)
        #expect(projects[0].roomID == "!b:example.com")
    }

    // MARK: - Helpers

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

    private func makeService(rooms: [RoomSummary],
                             goalEvents: @escaping (String) -> Result<[String], ClientProxyError>,
                             choiceEvents: @escaping (String) -> Result<[String], ClientProxyError>) -> AgentProjectIndexServiceProtocol {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.getRoomStateEventsRawRoomIDEventTypeClosure = { roomID, eventType in
            switch eventType {
            case AgentGoalStateEvent.eventType:
                goalEvents(roomID)
            default:
                choiceEvents(roomID)
            }
        }

        let roomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded(rooms)))

        return AgentProjectIndexService(clientProxy: clientProxy, roomSummaryProvider: roomSummaryProvider)
    }
}
