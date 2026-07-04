# Agent Tasks Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new bottom tab aggregating `io.element.agent.canvas.steps` task state across all joined rooms, per `docs/superpowers/specs/2026-07-05-agent-tasks-tab-design.md`.

**Architecture:** ClientProxy gains a lightweight cross-room state read; a new `AgentTaskIndexService` aggregates per-room state events into `AgentTaskSummary` values driven by the room summary provider; a new MVVM-C `AgentTasksScreen` renders them in a new `HomeTab.tasks` tab and routes taps to the owning room.

**Tech Stack:** Swift 6.2 / SwiftUI / Combine, Compound design system, Sourcery mocks, Swift Testing.

## Global Constraints

- **No local Swift toolchain on this Linux machine.** Build/test cycle per task:
  1. Edit sources in this repo (Linux), commit, `git push coderkaka feature/space-tab-bar`.
  2. `ssh -i ~/.ssh/id_ed25519_kaka zhangqiong@mac-mini.tail2edbaa.ts.net 'cd ~/Code/element-x-ios && git pull --ff-only origin feature/space-tab-bar'`
  3. On the Mac (all via the same ssh): regenerate when needed — new files: `xcodegen generate`; protocol/preview changes: `~/.local/bin/sourcery --config Tools/Sourcery/AutoMockableConfig.yml` (and `PreviewTestsConfig.yml` for new previews).
  4. Build: `cd ~/Code/element-x-ios && xcodebuild build -project ElementX.xcodeproj -scheme ElementX -configuration Debug -destination 'platform=iOS,id=A0B22EAF-7313-5DBF-B829-A1812C1CCD82' CODE_SIGN_STYLE=Automatic` — **expected to fail ONLY at `CodeSign … errSecInternalComponent`** (SSH keychain limitation). Zero `error:` lines before CodeSign = success.
  5. Unit tests: `xcodebuild test -project ElementX.xcodeproj -scheme UnitTests -destination 'platform=iOS Simulator,id=0D2C8E22-14AF-48A3-A7CE-552709547033' -only-testing:UnitTests/<TestClass>`.
  6. If the Mac's `xcodegen`/`sourcery` changed `project.pbxproj`/`Generated/` files: commit those **on the Mac**, push, and `git pull` back on Linux before the next task. `project.pbxproj` is now a tracked file (fork-local config baked in) — commit it, do not revert it.
- The `MatrixRustSDK` package resolves to the local `../matrix-rust-sdk-pinned` checkout on the Mac; `getStateEventsRaw(eventType:)` exists there (commit 86916c2). Do not bump or change the package reference.
- **Do NOT run or install anything on the physical device** — the user tests in the morning.
- Wire fields snake_case (`task_id`); Swift API per Swift API Design Guidelines (`taskID`, not `taskId`).
- New English strings → `UntranslatedL10n` (in `ElementX/Resources/Localizations/Untranslated.strings` — key style `screen_agent_tasks_*`), never `Localizable.strings`.
- Previews use `PreviewProvider` + `TestablePreview`, not `#Preview`.
- SwiftFormat runs as a pre-commit hook **on the Mac only**; if a Mac-side commit is aborted with "SwiftFormat warnings", re-stage the auto-fixed files and commit again. On Linux there is no hook — match existing style manually (4-space indent, no trailing whitespace).

---

### Task 1: ClientProxy cross-room state read

**Files:**
- Modify: `ElementX/Sources/Services/Client/ClientProxyProtocol.swift`
- Modify: `ElementX/Sources/Services/Client/ClientProxy.swift`
- (Mac) Regenerate: `ElementX/Sources/Mocks/Generated/GeneratedMocks.swift` via Sourcery

**Interfaces:**
- Produces: `func getRoomStateEventsRaw(roomID: String, eventType: String) async -> Result<[String], ClientProxyError>` on `ClientProxyProtocol`, plus the Sourcery-generated mock members (`getRoomStateEventsRawRoomIDEventTypeReturnValue` etc.) Task 2's tests rely on.

- [ ] **Step 1: Add the protocol requirement** — in `ClientProxyProtocol.swift`, near the other room-related functions:

```swift
/// Reads all state events of a given type in a room (one raw event JSON string per state
/// key), from the local store. Deliberately not on `JoinedRoomProxy`: building one spins up
/// a live timeline, far too heavy for iterating every joined room.
func getRoomStateEventsRaw(roomID: String, eventType: String) async -> Result<[String], ClientProxyError>
```

- [ ] **Step 2: Implement in `ClientProxy.swift`** (near `loadOrFetchEventDetails`-style helpers; follow the file's existing `do/catch` + `MXLog.error` + `.sdkError` idiom):

```swift
func getRoomStateEventsRaw(roomID: String, eventType: String) async -> Result<[String], ClientProxyError> {
    do {
        guard let room = try client.getRoom(roomId: roomID) else {
            return .success([])
        }
        return try await .success(room.getStateEventsRaw(eventType: eventType))
    } catch {
        MXLog.error("Failed reading state events eventType: \(eventType) roomID: \(roomID) with error: \(error)")
        return .failure(.sdkError(error))
    }
}
```

- [ ] **Step 3: Sync to Mac, regenerate mocks, build** (Global Constraints loop; Sourcery `AutoMockableConfig.yml` required because the protocol changed). Expected: build reaches CodeSign with zero `error:` lines; `grep -c getRoomStateEventsRaw ElementX/Sources/Mocks/Generated/GeneratedMocks.swift` > 0.
- [ ] **Step 4: Commit** (Mac-side commit including regenerated mocks + pbxproj if touched, message: `Add ClientProxy.getRoomStateEventsRaw for cross-room state reads`), push, pull back on Linux.

---

### Task 2: AgentTaskIndexService

**Files:**
- Create: `ElementX/Sources/Services/AgentTasks/AgentTaskSummary.swift`
- Create: `ElementX/Sources/Services/AgentTasks/AgentTaskIndexService.swift`
- Create: `ElementX/Sources/Services/AgentTasks/AgentTaskIndexServiceProtocol.swift`
- Test: `UnitTests/Sources/AgentTaskIndexServiceTests.swift`

**Interfaces:**
- Consumes: `ClientProxyProtocol.getRoomStateEventsRaw` (Task 1); `RoomSummaryProviderProtocol.roomListPublisher` (existing, `CurrentValuePublisher<[RoomSummary], Never>`; `RoomSummary` has `id: String` (room ID) and `name: String`).
- Produces: `AgentTaskIndexServiceProtocol` with `var tasksPublisher: CurrentValuePublisher<[AgentTaskSummary], Never> { get }` and `func start()`; `AgentTaskSummary` as specced. Sourcery mock `AgentTaskIndexServiceMock` for Task 3/4.

- [ ] **Step 1: Models** — `AgentTaskSummary.swift`:

```swift
import Foundation

struct AgentTaskSummary: Identifiable, Equatable {
    let roomID: String
    let roomName: String
    let taskID: String
    /// `nil` when the state event doesn't carry a title (older agents) — UI shows `taskID`.
    let title: String?
    let isResolved: Bool
    let doneStepCount: Int
    let totalStepCount: Int

    var id: String { "\(roomID)|\(taskID)" }
}

/// Parses the full raw state event JSON returned by `getRoomStateEventsRaw` for
/// `io.element.agent.canvas.steps` (state key = task_id).
struct AgentTaskStateEvent: Decodable {
    static let eventType = "io.element.agent.canvas.steps"

    let taskID: String
    let title: String?
    let isResolved: Bool
    let doneStepCount: Int
    let totalStepCount: Int

    private enum EventKeys: String, CodingKey {
        case stateKey = "state_key"
        case content
    }

    private struct Content: Decodable {
        let title: String?
        let status: String
        let steps: [CanvasStep]?
    }

    init(from decoder: Decoder) throws {
        let event = try decoder.container(keyedBy: EventKeys.self)
        taskID = try event.decode(String.self, forKey: .stateKey)
        let content = try event.decode(Content.self, forKey: .content)
        title = content.title
        isResolved = content.status == "done"
        let steps = content.steps ?? []
        doneStepCount = steps.count { $0.status == .done }
        totalStepCount = steps.count
    }

    init?(parsingFrom rawStateEventJSON: String) {
        guard let data = rawStateEventJSON.data(using: .utf8),
              let event = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = event
    }
}
```

(`CanvasStep` already exists in `AgentCanvasStepsRoomTimelineItemContent.swift` with a `Status` enum including `.done`.)

- [ ] **Step 2: Protocol** — `AgentTaskIndexServiceProtocol.swift`:

```swift
import Combine

// sourcery: AutoMockable
protocol AgentTaskIndexServiceProtocol {
    var tasksPublisher: CurrentValuePublisher<[AgentTaskSummary], Never> { get }
    func start()
}
```

(Match the `// sourcery: AutoMockable` annotation style used by other service protocols in the codebase — check one, e.g. `AppLockServiceProtocol`, and copy its exact annotation form.)

- [ ] **Step 3: Service** — `AgentTaskIndexService.swift`:

```swift
import Combine
import Foundation

class AgentTaskIndexService: AgentTaskIndexServiceProtocol {
    private let clientProxy: ClientProxyProtocol
    private let roomSummaryProvider: RoomSummaryProviderProtocol
    private var cancellables = Set<AnyCancellable>()

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
        Task { [weak self] in
            guard let self else { return }

            var tasks = [AgentTaskSummary]()
            for summary in summaries {
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
                                                  totalStepCount: stateEvent.totalStepCount))
                }
            }

            let unresolved = tasks.filter { !$0.isResolved }
            let resolved = tasks.filter(\.isResolved)
            tasksSubject.send(unresolved + resolved)
        }
    }
}
```

(Verify `RoomSummary`'s actual member names before using — `id`/`name` assumed; adjust to reality. If `name` is optional, fall back to the room ID.)

- [ ] **Step 4: Tests** — `AgentTaskIndexServiceTests.swift` with mocked `ClientProxyMock` + `RoomSummaryProviderMock` (both exist/are generated; check their `Configuration` conveniences). Cover: (a) parsing incl. missing `title` and missing `steps`; (b) unresolved-before-resolved ordering; (c) a room whose read fails is skipped while others still index; (d) unparseable event JSON skipped. Use the established `deferFulfillment` pattern for publisher assertions.
- [ ] **Step 5: Sync to Mac, xcodegen (new files) + sourcery (new protocol), build, run `-only-testing:UnitTests/AgentTaskIndexServiceTests`.** Expected: PASS.
- [ ] **Step 6: Commit** (`Add AgentTaskIndexService aggregating canvas task state across rooms`), push, pull back.

---

### Task 3: AgentTasksScreen (MVVM-C)

**Files:**
- Create: `ElementX/Sources/Screens/AgentTasksScreen/AgentTasksScreenModels.swift`
- Create: `ElementX/Sources/Screens/AgentTasksScreen/AgentTasksScreenViewModelProtocol.swift`
- Create: `ElementX/Sources/Screens/AgentTasksScreen/AgentTasksScreenViewModel.swift`
- Create: `ElementX/Sources/Screens/AgentTasksScreen/AgentTasksScreenCoordinator.swift`
- Create: `ElementX/Sources/Screens/AgentTasksScreen/View/AgentTasksScreen.swift`
- Modify: `ElementX/Resources/Localizations/Untranslated.strings`
- Test: `UnitTests/Sources/AgentTasksScreenViewModelTests.swift`

**Interfaces:**
- Consumes: `AgentTaskIndexServiceProtocol` (Task 2).
- Produces: `AgentTasksScreenCoordinator` with `actionsPublisher` emitting `enum AgentTasksScreenCoordinatorAction { case presentRoom(roomID: String) }`; Task 4 wires it.

Use `Tools/Scripts/Templates/SimpleScreenExample/` as the structural reference and `StateStoreViewModelV2` as the base class (same as the newest screens — check `CanvasStepsScreen` for the closest in-repo precedent and mirror it).

- [ ] **Step 1: Models** — ViewState holds `unresolvedTasks: [AgentTaskSummary]`, `resolvedTasks: [AgentTaskSummary]`; `enum AgentTasksScreenViewAction { case taskTapped(AgentTaskSummary) }`; `enum AgentTasksScreenViewModelAction { case presentRoom(roomID: String) }`.
- [ ] **Step 2: ViewModel** — subscribes `indexService.tasksPublisher` (store in `cancellables`), splits into the two arrays on each emission; `taskTapped` → `actionsSubject.send(.presentRoom(roomID:))`. Unit-testable with `AgentTaskIndexServiceMock`.
- [ ] **Step 3: View** — Compound `Form`/`.compoundList()` with two sections using `UntranslatedL10n.screenAgentTasksSectionActive` ("In progress") / `screenAgentTasksSectionDone` ("Done"); `ListRow` label: title-or-taskID, description room name, `details:` trailing text `"\(doneStepCount)/\(totalStepCount)"`, `kind: .button` sending `taskTapped`. Empty state: `screenAgentTasksEmpty` ("No agent tasks yet"). Previews: empty / mixed / all-done via `AgentTaskIndexServiceMock`, `TestablePreview` conformance.
- [ ] **Step 4: Strings** — add the three keys above to `Untranslated.strings`.
- [ ] **Step 5: ViewModel tests** — publisher-driven state split + `presentRoom` action, `deferFulfillment` pattern.
- [ ] **Step 6: Sync to Mac, xcodegen + sourcery (AutoMockable + PreviewTests configs), build, run `-only-testing:UnitTests/AgentTasksScreenViewModelTests`.** Snapshot recording is expected to FAIL-and-record on first run if the preview test harness demands references — record on the Mac (`ssh` run of the PreviewTests scheme is NOT required tonight; if preview tests can't run headless, note it in the report instead of fighting it).
- [ ] **Step 7: Commit** (`Add AgentTasksScreen listing cross-room agent tasks`), push, pull back.

---

### Task 4: Tasks tab wiring + room navigation

**Files:**
- Modify: `ElementX/Sources/FlowCoordinators/UserSessionFlowCoordinator.swift`

**Interfaces:**
- Consumes: `AgentTasksScreenCoordinator` (Task 3), `AgentTaskIndexService` (Task 2), existing `HomeTab` enum / `NavigationTabCoordinator.TabDetails` / `NavigationSplitCoordinator` machinery (see lines ~23, 37-43, 90-125), existing room-presentation path used by `AppRoute.room` handling (`handleAppRoute(.room(roomID:via:))`).

- [ ] **Step 1: Extend `HomeTab`** — `enum HomeTab: Hashable { case chats, tasks, spaces, search }`. Fix every exhaustive switch the compiler reports (there may be `default:`-less switches over `HomeTab` — touch each real consumer, mirroring how `spaces` is handled).
- [ ] **Step 2: Build the tab** — create `tasksSplitCoordinator` (`NavigationSplitCoordinator`) + `tasksTabDetails = .init(tag: HomeTab.tasks, title: UntranslatedL10n.screenHomeTabTasks, icon: \.listBulleted, selectedIcon: \.listBulleted)` (verify `\.listBulleted` exists in `CompoundIcons`; otherwise pick the closest checklist/list icon and note the substitution). Instantiate `AgentTaskIndexService(clientProxy:roomSummaryProvider:)` with the session's existing dependencies (find where `RoomSummaryProvider` is available in this flow coordinator — it's used for the chats tab), call `start()`, build `AgentTasksScreenCoordinator`, set as the split coordinator's root, insert the tab between chats and spaces in the `tabs` array.
- [ ] **Step 3: Route taps** — subscribe the coordinator's `actionsPublisher`; on `.presentRoom(roomID)` call the same path `AppRoute.room` uses (e.g. `handleAppRoute(.room(roomID: roomID, via: []), animated: true)`), which also switches to the chats tab if that's what the existing route handler does — follow its existing behavior, don't invent new switching logic.
- [ ] **Step 4: New string** — `screen_home_tab_tasks` = "Tasks" in `Untranslated.strings`.
- [ ] **Step 5: Sync to Mac, xcodegen + sourcery, full build + full `UnitTests` suite run** (not just one class — this task touches the app shell). Expected: build clean to CodeSign; test suite green.
- [ ] **Step 6: Commit** (`Add Tasks tab surfacing the cross-room agent task index`), push, pull back.
