# Phase C-1: IA 与命名(四 tab + 道管理入口 + 书信)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the terminal tab IA — 政事/差事/书信/检索 — by renaming tabs, removing the Spaces tab (management moves behind a gear chip in the 道 bar), and adding a DM-only 书信 tab on a dedicated room summary provider, per `docs/superpowers/specs/2026-07-05-phase-c-ia-goal-design.md` §1-§3.

**Architecture:** Pure client work, no SDK/protocol changes. Tab assembly lives in `UserSessionFlowCoordinator`; the 管理入口 mirrors the settings-sheet precedent (`navigationTabCoordinator.setSheetCoordinator`); 书信 is a lightweight MVVM-C screen over a new `messagesRoomSummaryProvider` (third provider, mirroring `alternateRoomSummaryProvider`), reusing `HomeScreenRoomCell`.

**Tech Stack:** Swift 6.2 / SwiftUI / Combine, Compound, Sourcery mocks, Swift Testing.

## Global Constraints

- **No local Swift toolchain here.** Per-task loop: edit on Linux → commit → `git push coderkaka feature/space-tab-bar` → `ssh -i ~/.ssh/id_ed25519_kaka zhangqiong@mac-mini.tail2edbaa.ts.net 'cd ~/Code/element-x-ios && git pull --ff-only origin feature/space-tab-bar'` → on the Mac regenerate as needed (`~/.local/bin/xcodegen` for new files; `~/.local/bin/sourcery --config Tools/Sourcery/AutoMockableConfig.yml` for protocol changes, plus `PreviewTestsConfig.yml`/`TestablePreviewsDictionary.yml`/`AccessibilityTests.yml` for new previews; `/opt/homebrew/bin/swiftgen config run --config Tools/SwiftGen/swiftgen-config.yml` for string changes) → build `xcodebuild build -project ElementX.xcodeproj -scheme ElementX -configuration Debug -destination 'platform=iOS,id=A0B22EAF-7313-5DBF-B829-A1812C1CCD82' CODE_SIGN_STYLE=Automatic` (**success = zero `error:` lines; the CodeSign `errSecInternalComponent` failure is expected and NOT an error**) → tests `xcodebuild test -scheme UnitTests -destination 'platform=iOS Simulator,id=0D2C8E22-14AF-48A3-A7CE-552709547033' -only-testing:...` → commit Mac-side generated changes on the Mac, push, pull back.
- MatrixRustSDK resolves to local `../matrix-rust-sdk-pinned` on the Mac — never touch package references.
- **No device installs** — user verifies later.
- UI copy is Chinese 御案体 via `Untranslated.strings` (base/en file — fork-local decision). Code identifiers stay functional English (`messages`, `projects`). Never edit `Localizable.strings` (upstream Localazy keys like `screen_home_tab_chats` stay; we stop *using* them instead).
- Wire fields snake_case; previews use `PreviewProvider` + `TestablePreview`; SwiftFormat pre-commit hook on the Mac may abort once with auto-fixes — re-stage and retry.
- Do NOT run the PreviewTests scheme (snapshot baselines are recorded by the user on-device later); regenerating the preview-test sources via Sourcery IS required for new previews.
- Known pre-existing test failures (~14, Chinese-locale string asserts and friends) are NOT yours; compare failure lists against the ledger before blaming your change.

---

### Task 1: 御案体命名落地(tab 标题与差事 tab 文案)

**Files:**
- Modify: `ElementX/Resources/Localizations/en.lproj/Untranslated.strings`
- Modify: `ElementX/Sources/FlowCoordinators/UserSessionFlowCoordinator.swift:93,102,119`
- Modify: `ElementX/Sources/Screens/AgentTasksScreen/View/AgentTasksScreen.swift` (navigationTitle, if it has a hardcoded/L10n one — check and switch to `UntranslatedL10n.screenHomeTabTasks`)

**Interfaces:**
- Consumes: existing `UntranslatedL10n` accessors.
- Produces: new key `screen_home_tab_projects` = `政事` (accessor `UntranslatedL10n.screenHomeTabProjects`); changed values for `screen_home_tab_tasks` → `差事`, `screen_home_tab_search` → `检索`, `screen_agent_tasks_section_active` → `在办`, `screen_agent_tasks_section_done` → `已结`, `screen_agent_tasks_empty` → `暂无差事`. Task 3 consumes `screen_home_tab_messages` = `书信` and `screen_messages_empty` = `暂无书信` — add both keys NOW so strings ship in one commit.

- [ ] **Step 1:** In `Untranslated.strings` apply the value changes and new keys listed above (keep alphabetical-ish grouping with the existing `screen_home_tab_*` block).
- [ ] **Step 2:** In `UserSessionFlowCoordinator.swift`:
  - line 93: `chatsTabDetails = .init(tag: HomeTab.chats, title: UntranslatedL10n.screenHomeTabProjects, icon: \.chat, selectedIcon: \.chatSolid)`
  - lines 102/119 need no code change (key values changed, accessors identical).
- [ ] **Step 3:** Check `AgentTasksScreen.swift` for its `navigationTitle` — if it doesn't already use `UntranslatedL10n.screenHomeTabTasks`, switch it so the nav bar also reads 差事.
- [ ] **Step 4:** Mac loop: swiftgen regen → build → run `-only-testing:UnitTests/AgentTasksScreenViewModelTests` (should be unaffected; it asserts VM state, not copy — if any test asserts English copy, update the assertion to the new value in the same commit). Commit (`Rename tabs to 御案体: 政事/差事/检索, and agent tasks copy`), push, pull back.

---

### Task 2: Spaces tab 移除 + 道管理入口

**Files:**
- Modify: `ElementX/Sources/FlowCoordinators/UserSessionFlowCoordinator.swift` (enum :23, spaces block :105-109, tabs array :132-140, `.start()` :222, observers :284)
- Modify: `ElementX/Sources/Screens/HomeScreen/View/Filters/SpaceTabBarView.swift`
- Modify: `ElementX/Sources/Screens/HomeScreen/View/HomeScreenContent.swift:120-131`
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenModels.swift` (view action + VM action)
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenViewModel.swift` (process viewAction)
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenCoordinator.swift` (action mapping)
- Modify: `ElementX/Sources/FlowCoordinators/ChatsTabFlowCoordinator.swift` (forward action, ~line 414 area)

**Interfaces:**
- Consumes: settings-sheet precedent `navigationTabCoordinator.setSheetCoordinator(_:dismissalCallback:)` (`UserSessionFlowCoordinator.swift:375+`); existing `spacesTabFlowCoordinator` + its `spacesSplitCoordinator` (both kept, just not a tab anymore).
- Produces: action chain `HomeScreenViewAction.manageSpaces` → `HomeScreenViewModelAction.presentSpaceManagement` → `HomeScreenCoordinatorAction.presentSpaceManagement` → `ChatsTabFlowCoordinatorAction.showSpaceManagement` → `UserSessionFlowCoordinator.presentSpaceManagement()`.

- [ ] **Step 1:** `UserSessionFlowCoordinator.swift`:
  - `enum HomeTab: Hashable { case chats, tasks, messages, search }` — remove `spaces` now; `messages` lands here (Task 3 uses it; adding the case early keeps this file touched once per concern). Compiler will flag every `.spaces` reference — that's the removal checklist.
  - Keep the `spacesTabFlowCoordinator` property and its construction, but make the split coordinator reachable: promote `let spacesSplitCoordinator` from an init local to a stored `private let`. Delete `spacesTabDetails` (property + construction). Remove the spaces entry from the `tabs` array.
  - Replace the unconditional `spacesTabFlowCoordinator.start()` (line 222) with a lazy-start flag:
    ```swift
    private var spacesFlowStarted = false

    private func presentSpaceManagement() {
        if !spacesFlowStarted {
            spacesFlowStarted = true
            spacesTabFlowCoordinator.start()
        }
        navigationTabCoordinator.setSheetCoordinator(spacesSplitCoordinator)
    }
    ```
  - The existing `spacesTabFlowCoordinator.actionsPublisher` sink (line 284) stays verbatim.
- [ ] **Step 2:** `SpaceTabBarView.swift`: add `let onManageTapped: () -> Void` and, after `RoomFiltersButton`, a gear button in the same trailing HStack:
    ```swift
    Button(action: onManageTapped) {
        CompoundIcon(\.settings, size: .small, relativeTo: .compound.bodyMD)
            .foregroundColor(.compound.iconSecondary)
    }
    .accessibilityLabel(UntranslatedL10n.actionManageSpaces)
    ```
    Add key `action_manage_spaces` = `管理诸道` to `Untranslated.strings`. Update the view's previews for the new parameter.
- [ ] **Step 3:** Wire the chain: `HomeScreenContent.swift` passes `onManageTapped: { context.send(viewAction: .manageSpaces) }`; add `case manageSpaces` to `HomeScreenViewAction` and `case presentSpaceManagement` to `HomeScreenViewModelAction` (`HomeScreenModels.swift`); in `HomeScreenViewModel.process(viewAction:)` map one to the other; add `case presentSpaceManagement` to `HomeScreenCoordinatorAction` and map it in the coordinator's action sink (next to `presentSettingsScreen`); add `case showSpaceManagement` to `ChatsTabFlowCoordinatorAction`, forward it where `presentSettingsScreen → .showSettings` is forwarded (~line 414); in `UserSessionFlowCoordinator`'s `chatsTabFlowCoordinator.actionsPublisher` sink add `case .showSpaceManagement: presentSpaceManagement()`.
- [ ] **Step 4:** Grep the repo for `HomeTab.spaces` / `.spaces` stragglers (e.g. tab restoration, deep links) and fix each — expected: none beyond this file; there are no space `AppRoute` cases.
- [ ] **Step 5:** Mac loop: build (xcodegen NOT needed — no file add/remove; sourcery preview regen IS needed — `SpaceTabBarView` previews changed signature). Run `-only-testing:UnitTests/HomeScreenViewModelTests`. Commit (`Remove the Spaces tab; space management opens from a gear chip in the 道 bar`), push, pull back.

---

### Task 3: 书信 tab(MessagesScreen + 专用 provider)

**Files:**
- Modify: `ElementX/Sources/Services/Client/ClientProxy.swift` (`ClientProxyServices` ~:1455-1509, assignment block ~:241)
- Modify: `ElementX/Sources/Services/Client/ClientProxyProtocol.swift:143` area
- Modify: `ElementX/Sources/Mocks/ClientProxyMock.swift` (configuration default)
- Create: `ElementX/Sources/Screens/MessagesScreen/MessagesScreenModels.swift`
- Create: `ElementX/Sources/Screens/MessagesScreen/MessagesScreenViewModelProtocol.swift`
- Create: `ElementX/Sources/Screens/MessagesScreen/MessagesScreenViewModel.swift`
- Create: `ElementX/Sources/Screens/MessagesScreen/View/MessagesScreen.swift`
- Create: `ElementX/Sources/Screens/MessagesScreen/MessagesScreenCoordinator.swift`
- Modify: `ElementX/Sources/FlowCoordinators/UserSessionFlowCoordinator.swift` (messages tab assembly + observer)
- Test: `UnitTests/Sources/MessagesScreenViewModelTests.swift`

**Interfaces:**
- Consumes: `RoomSummaryProviderProtocol` (`roomListPublisher: CurrentValuePublisher<[RoomSummary], Never>`, `setFilter`), `HomeScreenRoom(summary:roomListActivityVisibility:seenInvites:)`, `HomeScreenRoomCell(room:isSelected:mediaProvider:action:)` — the cell's `action` closure takes a `HomeScreenViewAction`; only `.selectRoom(roomIdentifier:)` is emitted by cell taps.
- Produces: `ClientProxyProtocol.messagesRoomSummaryProvider: RoomSummaryProviderProtocol`; `MessagesScreenCoordinator(parameters:)` with `actionsPublisher` emitting `case presentRoom(roomID: String)`; `HomeTab.messages` tab between tasks and search.

- [ ] **Step 1:** `ClientProxyServices` (ClientProxy.swift ~:1490): add after `alternateRoomSummaryProvider`:
    ```swift
    messagesRoomSummaryProvider = RoomSummaryProvider(roomListService: roomListService,
                                                      eventStringBuilder: eventStringBuilder,
                                                      name: "MessagesRooms",
                                                      notificationSettings: notificationSettings,
                                                      appSettings: appSettings)
    try await messagesRoomSummaryProvider.setRoomList(roomListService.allRooms())
    ```
    plus the `let messagesRoomSummaryProvider: RoomSummaryProviderProtocol` field. In `ClientProxy` init assignment block (~:241) assign it and set its permanent filter once: `messagesRoomSummaryProvider.setFilter(.all(filters: [.people]))`. Add `var messagesRoomSummaryProvider: RoomSummaryProviderProtocol { get }` to `ClientProxyProtocol` with a doc comment (`/// DM-only provider backing the 书信 tab; its filter is fixed at init and never changes.`).
- [ ] **Step 2:** Regenerate mocks (Mac sourcery AutoMockable) and add a default in the hand-written `ClientProxyMock.swift` configuration: `underlyingMessagesRoomSummaryProvider = RoomSummaryProviderMock(.init())` — mirror exactly how `roomSummaryProvider`/`alternateRoomSummaryProvider` defaults are set there.
- [ ] **Step 3:** MessagesScreen quartet (lightweight, mirror `AgentTasksScreen`'s structure — read it first):
    ```swift
    // MessagesScreenModels.swift
    struct MessagesScreenViewState: BindableState {
        var rooms: [HomeScreenRoom] = []
    }
    enum MessagesScreenViewAction { case selectRoom(roomIdentifier: String) }
    enum MessagesScreenViewModelAction { case presentRoom(roomID: String) }
    ```
    ViewModel: `StateStoreViewModelV2`, init takes `roomSummaryProvider: RoomSummaryProviderProtocol, appSettings: AppSettings, mediaProvider: MediaProviderProtocol` (mediaProvider passed via the VM context as HomeScreen does — check `StateStoreViewModelV2`'s `mediaProvider` init parameter and use it); subscribes `roomSummaryProvider.roomListPublisher.receive(on: DispatchQueue.main)` and maps `HomeScreenRoom(summary:roomListActivityVisibility:seenInvites:)` with `appSettings.roomListActivityVisibility` / `appSettings.seenInvites` into `state.rooms`; `.selectRoom` → `actionsSubject.send(.presentRoom(roomID:))`.
    View: `List` of `HomeScreenRoomCell(room:isSelected:false, mediaProvider: context.mediaProvider) { action in if case .selectRoom(let id) = action { context.send(viewAction: .selectRoom(roomIdentifier: id)) } }`, `.listStyle(.plain)`, navigationTitle `UntranslatedL10n.screenHomeTabMessages`; empty state (`rooms.isEmpty`): centered `Text(UntranslatedL10n.screenMessagesEmpty)` in `bodyLG`/`textSecondary` — same shape as `AgentTasksScreen`'s empty state. Previews: list + empty, `TestablePreview`.
    Coordinator: standard `CoordinatorProtocol` with `MessagesScreenCoordinatorParameters` (provider, appSettings, mediaProvider) and `actionsPublisher`.
- [ ] **Step 4:** `UserSessionFlowCoordinator`: build the messages tab after tasks (`messagesSplitCoordinator` + sidebar = `MessagesScreenCoordinator`; `TabDetails(tag: HomeTab.messages, title: UntranslatedL10n.screenHomeTabMessages, icon: \.userProfile, selectedIcon: \.userProfileSolid)`), insert into `tabs` between tasks and search, and in `setupObservers()` sink its `actionsPublisher`: `.presentRoom(roomID)` → `handleAppRoute(.room(roomID: roomID, via: []), animated: true)` (verbatim the AgentTasks pattern at :252-259 — note this opens the room in the chats tab's stack, which is the intended V1 behaviour: 书信 is an index, conversation happens in the main stack).
- [ ] **Step 5:** Unit tests (`MessagesScreenViewModelTests`, Swift Testing): provider mock emits 2 summaries → `state.rooms.count == 2` (use `deferFulfillment` on `context.observe(\.viewState.rooms)`); `.selectRoom` view action → `.presentRoom` VM action with matching ID.
- [ ] **Step 6:** Mac loop: xcodegen (new files) + sourcery (mocks + previews) → build → `-only-testing:UnitTests/MessagesScreenViewModelTests`. Commit (`Add the 书信 tab: a DM-only room list on a dedicated summary provider`), push, pull back.

---

### Task 4: 政事排除 DM + 过滤器收尾 + 全量回归

**Files:**
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenViewModel.swift:308-323` (`updateFilter`)
- Modify: `ElementX/Sources/Screens/RoomListFiltersScreen/` (exclude `.people` from the selectable filter list — find where the screen enumerates `RoomListFilter` cases)
- Test: `UnitTests/Sources/HomeScreenViewModelTests.swift` (extend)

**Interfaces:**
- Consumes: `RoomListFilter` enum (`RoomListFilterModels.swift:14`; note `incompatibleFilters` already knows `.people`/`.rooms` conflict), `updateFilter()`'s two `setFilter` call sites.
- Produces: 政事 (chats tab) shows group rooms only, in every filter state.

- [ ] **Step 1:** In `updateFilter()`, union `.rooms` into both non-search branches:
    ```swift
    if let spaceFilter = spaceFilterSubject.value {
        roomSummaryProvider?.setFilter(.rooms(roomsIDs: spaceFilter.descendants,
                                              filters: state.bindings.filtersState.activeFilters.set.union([.rooms])))
    } else {
        roomSummaryProvider?.setFilter(.all(filters: state.bindings.filtersState.activeFilters.set.union([.rooms])))
    }
    ```
    (Verify `activeFilters.set`'s element type is `RoomListFilter` and adjust the union spelling if it's an array — the intent is "always also apply `.rooms`".) Leave the `.search` branch alone: search should still find DMs (they're reachable via 书信 anyway, and search crossing both is a feature).
- [ ] **Step 2:** In the fork's `RoomListFiltersScreen`, remove `.people` from the user-selectable list (it would be a dead toggle now). Keep the enum case itself — 书信's provider uses it.
- [ ] **Step 3:** Extend `HomeScreenViewModelTests`: after VM setup, assert the provider mock received a filter containing `.rooms` (check how the existing tests observe `setFilter` calls on `RoomSummaryProviderMock` — there's a `setFilterReceivedFilter`-style recorded property from Sourcery).
- [ ] **Step 4:** Mac loop: build → **full** unit suite (`xcodebuild test -scheme UnitTests -destination 'platform=iOS Simulator,id=0D2C8E22-14AF-48A3-A7CE-552709547033'`), compare failures against the ledger's known-failures list (zero NEW failures required). Commit (`政事 tab shows group rooms only; DM filter chip removed`), push, pull back.

---

## 验收(user, device)

四 tab 显示为 政事/差事/书信/检索;政事顶部道 chip 条含 gear → 管理界面弹出可用;政事列表无 DM;书信列表只有 DM,点击进入对话;差事 tab 文案为 在办/已结/暂无差事。
