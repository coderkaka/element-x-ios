# Phase C-2: Goal Event 与政事增强 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land `io.element.agent.goal` as the project-room marker (SDK required_state + parser + cross-room index), enrich 政事 room cards with 差事进度 and 待批红点 plus priority sorting, and add the cross-room 请旨待批 strip, per `docs/superpowers/specs/2026-07-05-phase-c-ia-goal-design.md` §4-§9.

**Architecture:** One-line SDK fork change syncs the goal event; `AgentProjectIndexService` (clone of `AgentTaskIndexService`) indexes goals + pending choices in one room sweep; `HomeScreenViewModel` joins three publishers (rooms + tasks + projects) in `updateRooms()` — pure function, no new IO; a strip view sits under the 道 bar.

**Tech Stack:** Swift 6.2 / SwiftUI / Combine, Compound, Sourcery mocks, Swift Testing; Rust (one-line, SDK fork).

**Prerequisite:** Phase C-1 merged (uses its tab layout; no code dependency beyond that).

## Global Constraints

- **No local Swift toolchain here.** Per-task loop: edit on Linux → commit → `git push coderkaka feature/space-tab-bar` → `ssh -i ~/.ssh/id_ed25519_kaka zhangqiong@mac-mini.tail2edbaa.ts.net 'cd ~/Code/element-x-ios && git pull --ff-only origin feature/space-tab-bar'` → on the Mac regenerate as needed (`~/.local/bin/xcodegen` for new files; `~/.local/bin/sourcery --config Tools/Sourcery/AutoMockableConfig.yml` for protocol changes, plus `PreviewTestsConfig.yml`/`TestablePreviewsDictionary.yml`/`AccessibilityTests.yml` for new previews; `/opt/homebrew/bin/swiftgen config run --config Tools/SwiftGen/swiftgen-config.yml` for string changes) → build `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -configuration Debug -destination 'platform=iOS,id=A0B22EAF-7313-5DBF-B829-A1812C1CCD82' CODE_SIGN_STYLE=Automatic` (**success = zero `error:` lines; CodeSign `errSecInternalComponent` is expected and NOT an error**) → tests `xcodebuild test -scheme UnitTests -destination 'platform=iOS Simulator,id=0D2C8E22-14AF-48A3-A7CE-552709547033' -only-testing:...` → commit Mac-side generated changes on the Mac, push, pull back.
- **SDK fork loop (Task 1 only):** repo `~/Code/matrix-rust-sdk-pinned` on the Mac, branch `feature/agent-custom-events`. Build: `ssh … 'cd ~/Code/matrix-rust-sdk-pinned && CARGO_TARGET_DIR=/Volumes/DeveloperData/rust-target/matrix-rust-sdk-pinned cargo xtask swift build-framework --profile=reldbg'` (incremental, minutes). element-x-ios picks the output up automatically via the local package path — do not touch package references. Commit in the SDK repo with a descriptive message + changelog fragment placeholder, matching the existing 4 fork commits' style.
- UI copy is Chinese 御案体 via `Untranslated.strings` (base/en file — fork-local decision); keys/values in spec §9. Wire fields snake_case. Code identifiers functional English.
- PII logging rule: index/VM logs print roomID + event type + counts only — never goal `name`/`description` or choice `question`.
- Previews use `PreviewProvider` + `TestablePreview`. Do NOT run the PreviewTests scheme; regenerating preview-test sources via Sourcery IS required for new previews. SwiftFormat pre-commit hook may abort once — re-stage, retry.
- Known pre-existing test failures (~14, locale asserts) are NOT yours; compare against the ledger before blaming your change.
- **No device installs** — user verifies later with seeded state events.

---

### Task 1: SDK required_state + 协议 spec 更新

**Files:**
- Modify (Mac, SDK repo): `crates/matrix-sdk-ui/src/room_list_service/mod.rs:115-116`
- Modify (Mac): `~/homelab/element-agent-protocol.md`

**Interfaces:**
- Produces: goal state events flow into the local store via sliding sync (both the list and room-subscription `required_state` sites chain from the one const); the hermes work package (B') now includes goal + pending-choice obligations.

- [ ] **Step 1:** In `mod.rs` extend the const:
    ```rust
    const AGENT_EXTRA_REQUIRED_STATE: &[(&str, &str)] = &[
        ("io.element.agent.choice_request", "*"),
        ("io.element.agent.canvas.steps", "*"),
        ("io.element.agent.goal", "*"),
    ];
    ```
    Check whether any existing SDK test asserts the required_state contents (grep `AGENT_EXTRA_REQUIRED_STATE` and `io.element.agent` under `crates/matrix-sdk-ui/tests` and in-module tests) — update assertions if so.
- [ ] **Step 2:** Run the module's tests: `cargo test -p matrix-sdk-ui room_list_service` (same CARGO_TARGET_DIR). Expected: pass.
- [ ] **Step 3:** Rebuild the framework (command in Global Constraints). Then on the Mac in element-x-ios run a plain `xcodebuild build` to confirm the app still compiles against the fresh binaries (no API change — sanity only).
- [ ] **Step 4:** Commit in the SDK repo (`Sync io.element.agent.goal room state via the room list service`), matching the existing fork commits' changelog-fragment convention. Refresh the backup bundle: `git bundle create /Volumes/DeveloperData/backups/matrix-rust-sdk-agent-custom-events.bundle feature/agent-custom-events`.
- [ ] **Step 5:** Update `~/homelab/element-agent-protocol.md` (edit over SSH or scp round-trip):
  - New section for `io.element.agent.goal` (room-level, state_key `""`): schema `{name?, description?, status?: "active"|"done"|"archived"}`; presence = 立案; hermes writes it when a room becomes a project (and updates `status` on 结案); spec §Wire format has the exact JSON.
  - Extend the choice_request section: hermes MUST write `{"status": "pending", "question": "…"}` to the state key at ask time, and merge `{"status": "resolved", "resolved_selection": […]}` on resolution; client pending-detection = `resolved_selection` missing/empty. Backward compatibility note: rooms without the pending write simply don't appear in cross-room aggregation.
  - Bump the doc's 版本/日期 header line.
- [ ] **Step 6:** No element-x-ios commit in this task. Report the SDK commit hash for the ledger.

---

### Task 2: Goal/Choice 解析 + AgentProjectIndexService

**Files:**
- Create: `ElementX/Sources/Services/AgentTasks/AgentProjectSummary.swift`
- Create: `ElementX/Sources/Services/AgentTasks/AgentProjectIndexServiceProtocol.swift`
- Create: `ElementX/Sources/Services/AgentTasks/AgentProjectIndexService.swift`
- Modify: `ElementX/Sources/FlowCoordinators/UserSessionFlowCoordinator.swift:96-103` area (construct + start)
- Test: `UnitTests/Sources/AgentProjectIndexServiceTests.swift`

**Interfaces:**
- Consumes: `ClientProxyProtocol.getRoomStateEventsRaw(roomID:eventType:)`, `RoomSummaryProviderProtocol.roomListPublisher`, the `AgentTaskIndexService` implementation as the structural template (read it first: 1s debounce, per-room failure skip, sort, publisher shape), `AgentTaskStateEvent` as the parser template (`AgentTaskSummary.swift:28-66` — full-envelope decode with `EventKeys`/`Content`).
- Produces (Task 3/4 rely on these exact shapes):
    ```swift
    enum AgentProjectStatus: String { case active, done, archived }

    struct AgentProjectSummary: Identifiable, Equatable {
        let roomID: String
        let name: String?
        let description: String?
        let status: AgentProjectStatus
        var id: String { roomID }
    }

    struct AgentPendingChoiceSummary: Identifiable, Equatable {
        let roomID: String
        let eventID: String      // the state_key == original message event ID
        let question: String?
        var id: String { "\(roomID)|\(eventID)" }
    }

    // sourcery: AutoMockable
    protocol AgentProjectIndexServiceProtocol {
        var projectsPublisher: CurrentValuePublisher<[AgentProjectSummary], Never> { get }
        var pendingChoicesPublisher: CurrentValuePublisher<[AgentPendingChoiceSummary], Never> { get }
        func start()
    }
    ```

- [ ] **Step 1:** `AgentProjectSummary.swift`: the two summary structs above, plus two parsers mirroring `AgentTaskStateEvent`:
  - `AgentGoalStateEvent` — `static let eventType = "io.element.agent.goal"`; decodes envelope; content fields `name?/description?/status?` (CodingKeys snake_case; unknown status string → `.active`; missing status → `.active`).
  - `AgentChoiceStateIndexEvent` — `static let eventType = "io.element.agent.choice_request"`; decodes `state_key` + content `status?/question?/resolved_selection?: [String]`; computed `var isPending: Bool { (resolvedSelection ?? []).isEmpty }`.
  Both: `init?(parsingFrom rawStateEventJSON: String)`, tolerant decoding (`try?`/`decodeIfPresent`), return nil on garbage.
- [ ] **Step 2:** Write failing unit tests (Swift Testing) for the parsers: full goal / minimal goal (empty content → active) / each status value / bad JSON nil; choice pending (no selection), resolved (non-empty selection), pending with explicit status, question passthrough.
- [ ] **Step 3:** `AgentProjectIndexService`: clone `AgentTaskIndexService`'s structure — same init deps (`ClientProxyProtocol`, `RoomSummaryProviderProtocol`), same `start()` with 1s debounce on `roomListPublisher`, one `rebuildIndex` pass that for each room summary calls `getRoomStateEventsRaw` **twice** (goal type, choice type), parses, skips a room on either `.failure` (log count only), and sends both subjects. Projects sorted by roomID (stable); pending choices sorted by roomID.
- [ ] **Step 4:** Service tests: mock `ClientProxyMock` per-room returns (goal + one pending + one resolved choice) → publishers emit expected summaries; one room's failure doesn't empty the index (existing `AgentTaskIndexServiceTests` shows the mock recipe — mirror it).
- [ ] **Step 5:** `UserSessionFlowCoordinator`: construct `agentProjectIndexService` next to `agentTaskIndexService` (same deps), `.start()` immediately, store as `private let agentProjectIndexService: AgentProjectIndexServiceProtocol`. It gets handed to the chats flow in Task 3 — for now just constructed (unused-property warning is acceptable for one task; silence with `_ = agentProjectIndexService` nowhere — just leave it, SwiftLint tolerates stored lets).
- [ ] **Step 6:** Mac loop: xcodegen + sourcery (new protocol mock) → build → `-only-testing:UnitTests/AgentProjectIndexServiceTests` (plus the parser suite if separate). Commit (`Index agent goals and pending choices across rooms`), push, pull back.

---

### Task 3: 政事案卡片增强 + 排序

**Files:**
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenModels.swift:185+` (`HomeScreenRoom`)
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenViewModel.swift` (init deps, subscriptions, `updateRooms()` :381-398)
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenCoordinator.swift` + its `Parameters` (thread the two services in)
- Modify: `ElementX/Sources/FlowCoordinators/ChatsTabFlowCoordinator.swift` (pass services to HomeScreen construction; new init params from `UserSessionFlowCoordinator`)
- Modify: `ElementX/Sources/FlowCoordinators/UserSessionFlowCoordinator.swift` (pass `agentTaskIndexService` + `agentProjectIndexService` into `ChatsTabFlowCoordinator`)
- Modify: `ElementX/Sources/Screens/HomeScreen/View/HomeScreenRoomCell.swift` (badges)
- Modify: `ElementX/Resources/Localizations/en.lproj/Untranslated.strings` (`screen_home_room_task_progress` = `差事 %1$@/%2$@`)
- Test: `UnitTests/Sources/HomeScreenViewModelTests.swift` (extend)

**Interfaces:**
- Consumes: `AgentTaskIndexServiceProtocol.tasksPublisher` (`[AgentTaskSummary]` with `roomID/isResolved/doneStepCount/totalStepCount`), `AgentProjectIndexServiceProtocol` (Task 2 shapes).
- Produces: `HomeScreenRoom` gains `var isProject = false`, `var activeTaskCount = 0`, `var doneTaskCount = 0`, `var pendingChoiceCount = 0`; 政事 list sorted 待批 → 在办 → provider order.

- [ ] **Step 1:** Add the four fields to `HomeScreenRoom` with defaults (so `placeholder()` and existing inits stay valid). Progress display value = `doneTaskCount`/`totalTaskCount` where `totalTaskCount = activeTaskCount + doneTaskCount` — expose `var totalTaskCount: Int { activeTaskCount + doneTaskCount }`.
- [ ] **Step 2:** Thread the services: `HomeScreenViewModel` init gains `agentTaskIndexService:` + `agentProjectIndexService:`; subscribe both publishers (`receive(on: DispatchQueue.main)`), store latest values in private vars, call `updateRooms()` on emission. `HomeScreenCoordinator.Parameters` + `ChatsTabFlowCoordinator` + `UserSessionFlowCoordinator` pass them down (follow how existing dependencies like `roomSummaryProvider` travel this exact path — read the chain first).
- [ ] **Step 3:** In `updateRooms()` join and sort:
    ```swift
    let tasksByRoom = Dictionary(grouping: latestTaskSummaries, by: \.roomID)
    let projectRoomIDs = Set(latestProjects.map(\.roomID))
    let pendingByRoom = Dictionary(grouping: latestPendingChoices, by: \.roomID)

    for summary in roomSummaryProvider.roomListPublisher.value {
        var room = HomeScreenRoom(summary: summary, roomListActivityVisibility: ..., seenInvites: ...)
        if let roomID = room.roomID {
            room.isProject = projectRoomIDs.contains(roomID)
            let tasks = tasksByRoom[roomID] ?? []
            room.activeTaskCount = tasks.count(where: { !$0.isResolved })
            room.doneTaskCount = tasks.count(where: \.isResolved)
            room.pendingChoiceCount = pendingByRoom[roomID]?.count ?? 0
        }
        rooms.append(room)
    }
    // 稳定重排:待批 → 在办 → 其余按 provider 原序
    let pending = rooms.filter { $0.pendingChoiceCount > 0 }
    let active = rooms.filter { $0.pendingChoiceCount == 0 && $0.activeTaskCount > 0 }
    let rest = rooms.filter { $0.pendingChoiceCount == 0 && $0.activeTaskCount == 0 }
    state.rooms = pending + active + rest
    ```
    (Adapt to the real surrounding code; `filter` preserves provider order within each group — that IS the stability guarantee, note it in a one-line comment.)
- [ ] **Step 4:** `HomeScreenRoomCell` footer badge `HStack` (:133-158): prepend two conditional elements — a red-tinted badge when `room.pendingChoiceCount > 0` (use `CompoundIcon(\.error, size: .xSmall, …)` in `.compound.iconCriticalPrimary`, or match the existing mention-badge idiom — pick whichever matches the row's visual language, previews decide) and a `Text(UntranslatedL10n.screenHomeRoomTaskProgress(String(room.doneTaskCount), String(room.totalTaskCount)))` caption in `bodyXS`/`textSecondary` when `room.totalTaskCount > 0`. Add previews for: project room with tasks, room with pending, plain room (extend the cell's existing preview provider).
- [ ] **Step 5:** Extend `HomeScreenViewModelTests`: seed both service mocks' publishers, assert rooms carry counts and the sorted order (pending room first even when provider order says otherwise; provider order preserved within groups). Use the established `deferFulfillment` pattern.
- [ ] **Step 6:** Mac loop: sourcery (previews) → build → `-only-testing:UnitTests/HomeScreenViewModelTests` → commit (`政事 cards show 差事 progress and 待批 badge, priority sorted`), push, pull back.

---

### Task 4: 请旨待批横条 + 全量回归

**Files:**
- Create: `ElementX/Sources/Screens/HomeScreen/View/PendingChoicesStripView.swift`
- Modify: `ElementX/Sources/Screens/HomeScreen/View/HomeScreenContent.swift` (`topSection`, under the SpaceTabBarView block)
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenModels.swift` (view state + actions + sheet binding)
- Modify: `ElementX/Sources/Screens/HomeScreen/View/HomeScreen.swift` (sheet)
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenViewModel.swift` (strip data + tap handling)
- Modify: `ElementX/Resources/Localizations/en.lproj/Untranslated.strings` (spec §9: `screen_home_pending_choices_strip`, `screen_home_pending_choices_sheet_title`)
- Test: `UnitTests/Sources/HomeScreenViewModelTests.swift` (extend)

**Interfaces:**
- Consumes: `latestPendingChoices` + space filter (`spaceFilterSubject.value?.descendants`) from Task 3's VM state; existing `.selectRoom`/`presentRoom` room-opening path.
- Produces: strip visible when the (道-filtered) pending list is non-empty; tap → 1 pending: open its room; >1: sheet listing `question + room name`, row tap opens room.

- [ ] **Step 1:** View state: add to `HomeScreenViewState` `var pendingChoices: [HomeScreenPendingChoice] = []` where
    ```swift
    struct HomeScreenPendingChoice: Identifiable, Equatable {
        let roomID: String
        let eventID: String
        let question: String?
        let roomName: String?
        var id: String { "\(roomID)|\(eventID)" }
    }
    ```
    plus binding `var isPresentingPendingChoices = false` in the bindings struct, and view actions `case tappedPendingChoicesStrip`, `case selectPendingChoice(roomID: String)`.
- [ ] **Step 2:** VM: build `state.pendingChoices` whenever pending/room data changes (inside `updateRooms()` — join `latestPendingChoices` with the provider's summaries for `roomName`, intersect with `spaceFilterSubject.value?.descendants` when a 道 is selected). Handle actions: `tappedPendingChoicesStrip` → if `count == 1` treat as `selectPendingChoice` else `state.bindings.isPresentingPendingChoices = true`; `selectPendingChoice(roomID)` → close sheet, send the existing room-opening action (`.presentRoom(roomIdentifier: roomID)` — reuse the exact action `.selectRoom` tapping a cell sends).
- [ ] **Step 3:** `PendingChoicesStripView`: a full-width button styled like `RoomTaskProgressChipView` (read it — same paddings/typography):
    `Text(UntranslatedL10n.screenHomePendingChoicesStrip(String(count)))` + chevron; red accent icon. Previews (1 / 3 pending) + `TestablePreview`. Insert in `topSection` below the SpaceTabBarView `Divider()`, `if !context.viewState.pendingChoices.isEmpty` — remember `topSection`'s outer `if` gate must also include this condition.
- [ ] **Step 4:** Sheet in `HomeScreen.swift` (mirror the existing filter sheets): `.sheet(isPresented: $context.isPresentingPendingChoices)` presenting a `List` of pending rows (`question` primary, `roomName` secondary, `ListRow`/`.compoundList()`), nav title `screen_home_pending_choices_sheet_title`, row tap sends `.selectPendingChoice(roomID:)`.
- [ ] **Step 5:** Tests: strip data joins room names; 道 filter intersects; single-pending tap opens room directly (assert VM action), multi opens sheet (assert binding).
- [ ] **Step 6:** Mac loop: xcodegen + sourcery → build → **full** unit suite; compare against the ledger's known-failures list (zero NEW failures). Commit (`Cross-room 请旨待批 strip on the 政事 tab`), push, pull back.

---

## 验收(user, device;需先给测试房间写 goal state + pending choice state)

政事卡片:有 goal 的房间出现「差事 x/y」进度与待批红点,排序待批优先;顶部出现「N 件请旨待批」横条,单条直进房间、多条弹清单;hermes 侧按新协议写 pending 后无需客户端改动即可聚合。
