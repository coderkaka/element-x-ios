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
struct AgentTaskIndexServiceTests {
    // MARK: - Parsing

    @Test
    func stateEventParsing() {
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
    func stateEventParsingWithMissingTitleAndSteps() {
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
    func stateEventParsingFailures() {
        #expect(AgentTaskStateEvent(parsingFrom: "not json at all") == nil)
        #expect(AgentTaskStateEvent(parsingFrom: #"{"state_key":"task-3"}"#) == nil)
        #expect(AgentTaskStateEvent(parsingFrom: #"{"content":{"status":"done"}}"#) == nil)
    }

    // MARK: - Indexing

    @Test
    func unresolvedTasksAreListedBeforeResolvedOnes() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A"),
                                          .mock(id: "!b:example.com", name: "Room B")]) { roomID in
            switch roomID {
            case "!a:example.com":
                .success([Self.resolvedEventJSON])
            default:
                .success([Self.unresolvedEventJSON])
            }
        }

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
    func failingRoomIsSkippedWhileOthersStillIndex() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A"),
                                          .mock(id: "!b:example.com", name: "Room B")]) { roomID in
            switch roomID {
            case "!a:example.com":
                .failure(.sdkError(ClientProxyMockError.generic))
            default:
                .success([Self.unresolvedEventJSON])
            }
        }

        let deferred = deferFulfillment(service.tasksPublisher) { !$0.isEmpty }
        service.start()
        let tasks = try await deferred.fulfill()

        #expect(tasks.count == 1)
        #expect(tasks[0].roomID == "!b:example.com")
        #expect(tasks[0].taskID == "task-unresolved")
    }

    @Test
    func unparseableEventIsSkipped() async throws {
        let service = makeService(rooms: [.mock(id: "!a:example.com", name: "Room A")]) { _ in
            .success(["not json at all", Self.unresolvedEventJSON])
        }

        let deferred = deferFulfillment(service.tasksPublisher) { !$0.isEmpty }
        service.start()
        let tasks = try await deferred.fulfill()

        #expect(tasks.count == 1)
        #expect(tasks[0].taskID == "task-unresolved")
    }

    // MARK: - Helpers

    private static let unresolvedEventJSON = """
    {"type":"io.element.agent.canvas.steps","state_key":"task-unresolved","content":\
    {"title":"Unresolved task","status":"in_progress","steps":[\
    {"id":"s1","label":"First","status":"done"},\
    {"id":"s2","label":"Second","status":"pending"}]}}
    """

    private static let resolvedEventJSON = """
    {"type":"io.element.agent.canvas.steps","state_key":"task-resolved","content":\
    {"title":"Resolved task","status":"done","steps":[{"id":"s1","label":"First","status":"done"}]}}
    """

    private func makeService(rooms: [RoomSummary],
                             stateEvents: @escaping (String) -> Result<[String], ClientProxyError>) -> AgentTaskIndexServiceProtocol {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.getRoomStateEventsRawRoomIDEventTypeClosure = { roomID, _ in stateEvents(roomID) }

        let roomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded(rooms)))

        return AgentTaskIndexService(clientProxy: clientProxy, roomSummaryProvider: roomSummaryProvider)
    }
}
