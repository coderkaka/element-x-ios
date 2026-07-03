# Room Filters Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the always-visible `RoomListFiltersView` chip row on the Home screen with a single button appended (fixed, non-scrolling) to the end of the `SpaceTabBarView` row; tapping it opens a new sheet (`RoomListFiltersScreen`) with the same six filters as toggleable rows, with no loss of filtering capability.

**Architecture:** Follows the existing `ChatsSpaceFiltersScreen` precedent exactly: a sheet-presented screen with Models/ViewModel/ViewModelProtocol/View (no Coordinator — the view model itself is `Identifiable` and stored as an optional in `HomeScreenViewStateBindings`, presented via `.sheet(item:)`). The new screen owns its own copy of `RoomListFiltersState` (the same struct `RoomListFiltersView` already binds to today — no changes to that struct), mutates it via its existing `activateFilter`/`deactivateFilter`/`clearFilters` methods, and reports the updated state back to `HomeScreenViewModel` live (on every toggle, not batched), which writes it into `state.bindings.filtersState` — the exact same field the existing reactive room-filtering pipeline already watches, so no new plumbing is needed there.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing (`@Test`/`#expect`), Compound (`ListRow`, `.compoundList()`, `CompoundIcon`, `.overlayBadge`), `StateStoreViewModelV2`.

## Global Constraints

- New user-facing strings go in `Untranslated.strings` (English only, never edit `Localizable.strings` — it's Localazy-managed), per AGENTS.md.
- Every new interactive control gets an `AccessibilityIdentifiers` entry, following the existing `HomeScreen.spaceFilters` convention (`AccessibilityIdentifiers.swift:110-120`).
- `nonisolated` is NOT needed here — screens/view models default to `MainActor` in this target (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
- No Coordinator file for this screen — confirmed precedent is `ChatsSpaceFiltersScreen`, which has none (directory `ElementX/Sources/Screens/ChatsSpaceFiltersScreen/` contains only Models/ViewModel/ViewModelProtocol/View).
- `StateStoreViewModelV2`'s base init is `init(initialViewState: State, mediaProvider: MediaProviderProtocol? = nil)` (`StateStoreViewModelV2.swift:35`) — `mediaProvider` defaults to `nil` and can be omitted; this screen has no avatars/media.
- `RoomListFiltersState.activateFilter(_:)` (`RoomListFilterModels.swift:111-120`) calls `fatalError` if you activate a filter that's mutually exclusive with an already-active one — every call site in this plan must check `availableFilters.contains(filter)` first.

## Task 1: Add strings and accessibility identifier

**Files:**
- Modify: `ElementX/Resources/Localizations/en.lproj/Untranslated.strings`
- Modify: `ElementX/Sources/Other/AccessibilityIdentifiers.swift`

**Interfaces:**
- Produces: `L10n.screenRoomlistFiltersTitle`, `L10n.a11yRoomListFiltersButton`, `AccessibilityIdentifiers.homeScreen.roomListFilters`.

This task has no test of its own — it's pure data feeding later tasks' UI code, verified indirectly when those tasks' previews/tests reference these symbols.

- [ ] **Step 1: Add the two new strings**

Add to `ElementX/Resources/Localizations/en.lproj/Untranslated.strings` (alphabetical position doesn't matter in this file — append at the end, before the closing `"untranslated"` line is fine, order is not enforced):

```
"screen_roomlist_filters_title" = "Filters";
"a11y_room_list_filters_button" = "Show filters";
```

- [ ] **Step 2: Regenerate `L10n`**

Run: `swiftgen config run --config Tools/SwiftGen/swiftgen-config.yml`
Expected: `ElementX/Sources/Generated/Strings.swift` gains `internal static var screenRoomlistFiltersTitle: String` and `internal static var a11yRoomListFiltersButton: String`.

- [ ] **Step 3: Add the accessibility identifier**

In `ElementX/Sources/Other/AccessibilityIdentifiers.swift`, inside `struct HomeScreen` (currently lines 110-120), add a new line after `spaceFilters`:

```swift
    struct HomeScreen {
        let userAvatar = "home_screen-user_avatar"
        let recoveryKeyConfirmationBannerContinue = "home_screen-recovery_key_confirmation_continue"
        let startChat = "home_screen-start_chat"
        let spaceFilters = "home_screen-space_filters"
        let roomListFilters = "home_screen-room_list_filters"
        
        let roomNamePrefix = "home_screen-room_name"
        func roomName(_ name: String) -> String {
            "\(roomNamePrefix):\(name)"
        }
    }
```

- [ ] **Step 4: Build to confirm it compiles**

Run: `swift build` (or `xcodebuild build -scheme ElementX`)
Expected: builds cleanly — these are additive changes with no consumers yet.

- [ ] **Step 5: Commit**

```bash
git add ElementX/Resources/Localizations/en.lproj/Untranslated.strings ElementX/Sources/Generated/Strings.swift ElementX/Sources/Other/AccessibilityIdentifiers.swift
git commit -m "Add strings and accessibility identifier for the room filters sheet"
```

## Task 2: `RoomListFiltersScreen` models + view model

**Files:**
- Create: `ElementX/Sources/Screens/RoomListFiltersScreen/RoomListFiltersScreenModels.swift`
- Create: `ElementX/Sources/Screens/RoomListFiltersScreen/RoomListFiltersScreenViewModelProtocol.swift`
- Create: `ElementX/Sources/Screens/RoomListFiltersScreen/RoomListFiltersScreenViewModel.swift`
- Test: `UnitTests/Sources/RoomListFiltersScreenViewModelTests.swift`

**Interfaces:**
- Consumes: `RoomListFiltersState`, `RoomListFilter` (existing, `RoomListFilterModels.swift`).
- Produces: `RoomListFiltersScreenViewModelAction` (`.filtersChanged(RoomListFiltersState)`, `.dismiss`), `RoomListFiltersScreenViewState` (`filtersState: RoomListFiltersState`, default `Void` bindings), `RoomListFiltersScreenViewAction` (`.toggleFilter(RoomListFilter)`, `.clearFilters`, `.close`), `RoomListFiltersScreenViewModel(initialFiltersState: RoomListFiltersState)` conforming to `RoomListFiltersScreenViewModelProtocol, Identifiable`.

- [ ] **Step 1: Write the failing tests**

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

@MainActor
struct RoomListFiltersScreenViewModelTests {
    var viewModel: RoomListFiltersScreenViewModelProtocol
    var context: RoomListFiltersScreenViewModelType.Context { viewModel.context }

    init() {
        viewModel = RoomListFiltersScreenViewModel(initialFiltersState: .init(appSettings: .volatile()))
    }

    @Test
    func togglingAFilterActivatesIt() {
        #expect(context.viewState.filtersState.isFilterActive(.unreads) == false)
        context.send(viewAction: .toggleFilter(.unreads))
        #expect(context.viewState.filtersState.isFilterActive(.unreads) == true)
    }

    @Test
    func togglingAnActiveFilterDeactivatesIt() {
        context.send(viewAction: .toggleFilter(.favourites))
        #expect(context.viewState.filtersState.isFilterActive(.favourites) == true)
        context.send(viewAction: .toggleFilter(.favourites))
        #expect(context.viewState.filtersState.isFilterActive(.favourites) == false)
    }

    @Test
    func togglingAnIncompatibleFilterIsIgnored() {
        // .invites is incompatible with .people (RoomListFilterModels.swift:57-58).
        context.send(viewAction: .toggleFilter(.people))
        #expect(context.viewState.filtersState.isFilterActive(.people) == true)

        context.send(viewAction: .toggleFilter(.invites))
        #expect(context.viewState.filtersState.isFilterActive(.invites) == false, "Activating an incompatible filter must be a no-op, not a crash")
        #expect(context.viewState.filtersState.isFilterActive(.people) == true, "The original filter must remain active")
    }

    @Test
    func clearFiltersRemovesAllActiveFilters() {
        context.send(viewAction: .toggleFilter(.unreads))
        context.send(viewAction: .toggleFilter(.favourites))
        #expect(context.viewState.filtersState.isFiltering == true)

        context.send(viewAction: .clearFilters)
        #expect(context.viewState.filtersState.isFiltering == false)
    }

    @Test
    func toggleSendsLiveFiltersChangedAction() async throws {
        var receivedStates = [RoomListFiltersState]()
        let cancellable = viewModel.actionsPublisher.sink { action in
            if case .filtersChanged(let state) = action {
                receivedStates.append(state)
            }
        }

        context.send(viewAction: .toggleFilter(.rooms))

        #expect(receivedStates.count == 1)
        #expect(receivedStates.first?.isFilterActive(.rooms) == true)
        cancellable.cancel()
    }

    @Test
    func closeSendsDismissAction() async throws {
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            switch action {
            case .dismiss: true
            default: false
            }
        }

        context.send(viewAction: .close)

        try await deferred.fulfill()
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RoomListFiltersScreenViewModelTests`
Expected: FAIL — none of `RoomListFiltersScreenViewModel`/`RoomListFiltersScreenViewState`/`RoomListFiltersScreenViewAction`/`RoomListFiltersScreenViewModelAction` exist yet (compile error).

- [ ] **Step 3: Write the models file**

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum RoomListFiltersScreenViewModelAction {
    case filtersChanged(RoomListFiltersState)
    case dismiss
}

struct RoomListFiltersScreenViewState: BindableState {
    var filtersState: RoomListFiltersState
}

enum RoomListFiltersScreenViewAction: CustomStringConvertible {
    case toggleFilter(RoomListFilter)
    case clearFilters
    case close

    var description: String {
        switch self {
        case .toggleFilter(let filter): "Toggle \(filter)"
        case .clearFilters: "ClearFilters"
        case .close: "Close"
        }
    }
}
```

- [ ] **Step 4: Write the view model protocol**

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine

protocol RoomListFiltersScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<RoomListFiltersScreenViewModelAction, Never> { get }
    var context: RoomListFiltersScreenViewModelType.Context { get }
}
```

- [ ] **Step 5: Write the view model**

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias RoomListFiltersScreenViewModelType = StateStoreViewModelV2<RoomListFiltersScreenViewState, RoomListFiltersScreenViewAction>

class RoomListFiltersScreenViewModel: RoomListFiltersScreenViewModelType, RoomListFiltersScreenViewModelProtocol, Identifiable {
    private let actionsSubject: PassthroughSubject<RoomListFiltersScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<RoomListFiltersScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    let id = UUID()

    init(initialFiltersState: RoomListFiltersState) {
        super.init(initialViewState: RoomListFiltersScreenViewState(filtersState: initialFiltersState))
    }

    // MARK: - Public

    override func process(viewAction: RoomListFiltersScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .toggleFilter(let filter):
            if state.filtersState.isFilterActive(filter) {
                state.filtersState.deactivateFilter(filter)
            } else if state.filtersState.availableFilters.contains(filter) {
                state.filtersState.activateFilter(filter)
            } else {
                return
            }
            actionsSubject.send(.filtersChanged(state.filtersState))
        case .clearFilters:
            state.filtersState.clearFilters()
            actionsSubject.send(.filtersChanged(state.filtersState))
        case .close:
            actionsSubject.send(.dismiss)
        }
    }
}
```

Note the `else { return }` branch in `.toggleFilter`: if the filter is neither active nor currently available (i.e. it's excluded by `incompatibleFilters` from the current selection), the action is silently ignored instead of calling `activateFilter` — which would `fatalError`. Task 3's view only renders toggleable rows for filters that are active or available, so this branch is a safety net, not the primary guard.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter RoomListFiltersScreenViewModelTests`
Expected: PASS, all 6 tests green.

- [ ] **Step 7: Commit**

```bash
git add ElementX/Sources/Screens/RoomListFiltersScreen/RoomListFiltersScreenModels.swift ElementX/Sources/Screens/RoomListFiltersScreen/RoomListFiltersScreenViewModelProtocol.swift ElementX/Sources/Screens/RoomListFiltersScreen/RoomListFiltersScreenViewModel.swift UnitTests/Sources/RoomListFiltersScreenViewModelTests.swift
git commit -m "Add RoomListFiltersScreen models and view model"
```

## Task 3: `RoomListFiltersScreen` view

**Files:**
- Create: `ElementX/Sources/Screens/RoomListFiltersScreen/View/RoomListFiltersScreen.swift`

**Interfaces:**
- Consumes: `RoomListFiltersScreenViewModel`/`RoomListFiltersScreenViewState`/`RoomListFiltersScreenViewAction` (Task 2), `RoomListFilter.localizedName` (existing), Compound `ListRow`/`.compoundList()`/`ElementNavigationStack`/`ToolbarButton` (existing, used the same way `ChatsSpaceFiltersScreen` does).
- Produces: `RoomListFiltersScreen: View`.

This task has no unit test of its own — covered by Sourcery-generated snapshot/accessibility tests via `PreviewProvider, TestablePreview` conformance, same mechanism as every other screen in this codebase.

- [ ] **Step 1: Create the view**

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct RoomListFiltersScreen: View {
    @Bindable var context: RoomListFiltersScreenViewModel.Context

    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    ForEach(visibleFilters) { filter in
                        ListRow(label: .default(title: filter.localizedName),
                                kind: .toggle(binding(for: filter)))
                    }
                }
            }
            .compoundList()
            .toolbar { toolbar }
            .navigationTitle(L10n.screenRoomlistFiltersTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }

    /// Only show filters that are either already active, or still selectable given the current
    /// selection — mirrors `RoomListFiltersState.availableFilters` excluding mutually-exclusive
    /// options from the list entirely, matching today's chip-row behaviour.
    private var visibleFilters: [RoomListFilter] {
        RoomListFilter.allCases.filter { filter in
            context.viewState.filtersState.isFilterActive(filter) || context.viewState.filtersState.availableFilters.contains(filter)
        }
    }

    private func binding(for filter: RoomListFilter) -> Binding<Bool> {
        Binding<Bool>(get: {
            context.viewState.filtersState.isFilterActive(filter)
        }, set: { _, _ in
            context.send(viewAction: .toggleFilter(filter))
        })
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if context.viewState.filtersState.isFiltering {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.actionClear) {
                    context.send(viewAction: .clearFilters)
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            ToolbarButton(role: .close) {
                context.send(viewAction: .close)
            }
        }
    }
}

// MARK: - Previews

struct RoomListFiltersScreen_Previews: PreviewProvider, TestablePreview {
    static let noFiltersViewModel = RoomListFiltersScreenViewModel(initialFiltersState: .init(appSettings: .volatile()))
    static let someFiltersViewModel = RoomListFiltersScreenViewModel(initialFiltersState: .init(activeFilters: [.rooms, .favourites], appSettings: .volatile()))

    static var previews: some View {
        RoomListFiltersScreen(context: noFiltersViewModel.context)
            .previewDisplayName("No active filters")
        RoomListFiltersScreen(context: someFiltersViewModel.context)
            .previewDisplayName("Rooms + Favourites active")
    }
}
```

- [ ] **Step 2: Regenerate Sourcery-derived test files**

Run: `sourcery --config Tools/Sourcery/PreviewTestsConfig.yml` then `sourcery --config Tools/Sourcery/TestablePreviewsDictionary.yml` and `sourcery --config Tools/Sourcery/AccessibilityTests.yml`
Expected: `PreviewTests/Sources/GeneratedPreviewTests.swift` and the accessibility test file both gain new generated test functions for `RoomListFiltersScreen_Previews`.

- [ ] **Step 3: Build and run the generated snapshot test**

Run: `xcodebuild test -scheme ElementX -only-testing:PreviewTests/GeneratedPreviewTests/roomListFiltersScreen` (adjust the exact generated test identifier to whatever Step 2 produced)
Expected: PASS (first-run snapshot recording, consistent with this codebase's existing snapshot-testing setup).

- [ ] **Step 4: Commit**

```bash
git add ElementX/Sources/Screens/RoomListFiltersScreen/View/RoomListFiltersScreen.swift PreviewTests/Sources/GeneratedPreviewTests.swift AccessibilityTests/Sources/*.swift ElementX/Sources/Other/TestablePreview/TestablePreviewsDictionary.swift
git commit -m "Add RoomListFiltersScreen view"
```

## Task 4: Wire the sheet into `HomeScreen`

**Files:**
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenModels.swift`
- Modify: `ElementX/Sources/Screens/HomeScreen/HomeScreenViewModel.swift`
- Modify: `ElementX/Sources/Screens/HomeScreen/View/HomeScreen.swift`

**Interfaces:**
- Consumes: `RoomListFiltersScreenViewModel`/`RoomListFiltersScreenViewModelAction` (Task 2), `RoomListFiltersScreen` (Task 3).
- Produces: `HomeScreenViewAction.roomListFilters`, `HomeScreenViewStateBindings.roomListFiltersViewModel: RoomListFiltersScreenViewModel?`.

This task has no isolated unit test — it wires existing, already-tested pieces together. Verified by Task 5's manual/snapshot testing once the button exists to trigger it, and by re-running the full `HomeScreenViewModelTests` suite to confirm no regression.

- [ ] **Step 1: Add the new action case**

In `ElementX/Sources/Screens/HomeScreen/HomeScreenModels.swift`, add to the `HomeScreenViewAction` enum (currently lines 31-55, after `case spaceFilters`):

```swift
enum HomeScreenViewAction {
    case selectRoom(roomIdentifier: String)
    case detachRoom(roomIdentifier: String)
    case showRoomDetails(roomIdentifier: String)
    case leaveRoom(roomIdentifier: String)
    case confirmLeaveRoom(roomIdentifier: String)
    case reportRoom(roomIdentifier: String)
    case showSettings
    case startChat
    case setupRecovery
    case confirmRecoveryKey
    case resetEncryption
    case skipRecoveryKeyConfirmation
    case dismissNewSoundBanner
    case updateVisibleItemRange(Range<Int>)
    case spaceFilters
    case roomListFilters
    case markRoomAsUnread(roomIdentifier: String)
    case markRoomAsRead(roomIdentifier: String)
    case markRoomAsFavourite(roomIdentifier: String, isFavourite: Bool)
    
    case acceptInvite(roomIdentifier: String)
    case declineInvite(roomIdentifier: String)

    case selectSpaceFilter(SpaceServiceFilter?)
}
```

- [ ] **Step 2: Add the new bindable field**

In the same file, add to `HomeScreenViewStateBindings` (currently lines 168-177, after `spaceFiltersViewModel`):

```swift
struct HomeScreenViewStateBindings {
    var filtersState: RoomListFiltersState
    var searchQuery = ""
    var isSearchFieldFocused = false
    
    var alertInfo: AlertInfo<UUID>?
    var leaveRoomAlertItem: LeaveRoomAlertItem?
    
    var spaceFiltersViewModel: ChatsSpaceFiltersScreenViewModel?
    var roomListFiltersViewModel: RoomListFiltersScreenViewModel?
}
```

- [ ] **Step 3: Handle the action in the view model**

In `ElementX/Sources/Screens/HomeScreen/HomeScreenViewModel.swift`, add a new case to `process(viewAction:)`, right after the existing `.spaceFilters`/`.selectSpaceFilter` cases (currently lines 210-231):

```swift
        case .spaceFilters:
            if spaceFilterSubject.value != nil {
                spaceFilterSubject.send(nil)
            } else {
                state.bindings.spaceFiltersViewModel = ChatsSpaceFiltersScreenViewModel(spaceService: userSession.clientProxy.spaceService,
                                                                                        mediaProvider: userSession.mediaProvider)
                
                state.bindings.spaceFiltersViewModel?.actionsPublisher.sink { [weak self] action in
                    guard let self else { return }
                    
                    switch action {
                    case .confirm(let spaceServiceFilter):
                        spaceFilterSubject.send(spaceServiceFilter)
                        state.bindings.spaceFiltersViewModel = nil
                    case .cancel:
                        state.bindings.spaceFiltersViewModel = nil
                    }
                }
                .store(in: &cancellables)
            }
        case .selectSpaceFilter(let filter):
            spaceFilterSubject.send(filter)
        case .roomListFilters:
            let roomListFiltersViewModel = RoomListFiltersScreenViewModel(initialFiltersState: state.bindings.filtersState)
            
            roomListFiltersViewModel.actionsPublisher.sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .filtersChanged(let newFiltersState):
                    state.bindings.filtersState = newFiltersState
                case .dismiss:
                    state.bindings.roomListFiltersViewModel = nil
                }
            }
            .store(in: &cancellables)
            
            state.bindings.roomListFiltersViewModel = roomListFiltersViewModel
```

Because `state.bindings.filtersState` is the exact same field `RoomListFiltersView` was bound to before this plan removes it (Task 5), and the existing reactive pipeline (`HomeScreenViewModel.swift:157-171`) already watches `context.$viewState.map(\.bindings.filtersState.activeFilters)` to drive `updateFilter()`, assigning `state.bindings.filtersState = newFiltersState` on every toggle re-applies the room-list filter live — no separate wiring is needed here.

- [ ] **Step 4: Present the sheet**

In `ElementX/Sources/Screens/HomeScreen/View/HomeScreen.swift`, add a second `.sheet` modifier next to the existing one (currently lines 36-40):

```swift
            .sheet(item: $context.spaceFiltersViewModel) { vm in
                ChatsSpaceFiltersScreen(context: vm.context)
                    .navigationTransition(.zoom(sourceID: NavigationTransitionSourceID.spaceFilters,
                                                in: navigationTransitionNamespace))
            }
            .sheet(item: $context.roomListFiltersViewModel) { vm in
                RoomListFiltersScreen(context: vm.context)
            }
```

- [ ] **Step 5: Build and run existing HomeScreen tests to confirm no regression**

Run: `swift test --filter HomeScreenViewModelTests`
Expected: PASS — this task only adds new, additive code paths; nothing existing should break.

- [ ] **Step 6: Commit**

```bash
git add ElementX/Sources/Screens/HomeScreen/HomeScreenModels.swift ElementX/Sources/Screens/HomeScreen/HomeScreenViewModel.swift ElementX/Sources/Screens/HomeScreen/View/HomeScreen.swift
git commit -m "Wire RoomListFiltersScreen sheet into HomeScreen"
```

## Task 5: Collapse the chip row into a button on `SpaceTabBarView`

**Files:**
- Modify: `ElementX/Sources/Screens/HomeScreen/View/Filters/SpaceTabBarView.swift`
- Modify: `ElementX/Sources/Screens/HomeScreen/View/HomeScreenContent.swift`

**Interfaces:**
- Consumes: `HomeScreenViewAction.roomListFilters` (Task 4), sent from `HomeScreenContent.swift`'s call site.
- Produces: `SpaceTabBarView` gains two new parameters: `isFiltering: Bool`, `onFilterButtonTapped: () -> Void`.

This is the task that actually makes the button appear and removes the old chip row — the one to manually verify on device/simulator afterward.

- [ ] **Step 1: Add the button and restructure `SpaceTabBarView`'s body**

Replace the full contents of `ElementX/Sources/Screens/HomeScreen/View/Filters/SpaceTabBarView.swift` with:

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct SpaceTabBarView: View {
    let filters: [SpaceServiceFilter]
    let selectedFilter: SpaceServiceFilter?
    let mediaProvider: MediaProviderProtocol!
    let isFiltering: Bool
    let action: (SpaceServiceFilter?) -> Void
    let onFilterButtonTapped: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    SpaceTabChipView(name: L10n.screenRoomlistMainSpaceTitle,
                                     avatar: nil,
                                     isSelected: selectedFilter == nil,
                                     mediaProvider: mediaProvider) {
                        action(nil)
                    }

                    ForEach(filters) { filter in
                        SpaceTabChipView(name: filter.room.name,
                                         avatar: filter.room.avatar,
                                         isSelected: selectedFilter == filter,
                                         mediaProvider: mediaProvider) {
                            action(filter)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)

            RoomFiltersButton(isFiltering: isFiltering, action: onFilterButtonTapped)
                .padding(.trailing, 16)
        }
        .padding(.leading, 16)
    }
}

private struct SpaceTabChipView: View {
    let name: String
    let avatar: RoomAvatar?
    let isSelected: Bool
    let mediaProvider: MediaProviderProtocol!
    let action: () -> Void

    private var strokeColor: Color {
        isSelected ? .compound.bgActionPrimaryRest : .compound.borderInteractiveSecondary
    }

    private var backgroundColor: Color {
        isSelected ? .compound.bgActionPrimaryRest : .compound.bgCanvasDefault
    }

    private var foregroundColor: Color {
        isSelected ? .compound.textOnSolidPrimary : .compound.textPrimary
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20)
        Button(action: action) {
            HStack(spacing: 6) {
                if let avatar {
                    RoomAvatarImage(avatar: avatar,
                                    avatarSize: .custom(16),
                                    mediaProvider: mediaProvider)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .clipShape(.circle)
                        .accessibilityHidden(true)
                }
                Text(name)
                    .font(.compound.bodyMD)
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(shape.fill(backgroundColor))
            .overlay {
                shape
                    .inset(by: 0.5)
                    .stroke(strokeColor)
            }
            .drawingGroup()
        }
    }
}

private struct RoomFiltersButton: View {
    let isFiltering: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CompoundIcon(\.filter, size: .small, relativeTo: .compound.bodyLG)
                .foregroundStyle(.compound.iconPrimary)
                .padding(7)
                .background(.compound.bgSubtlePrimary, in: .circle)
                .overlayBadge(8, isBadged: isFiltering)
        }
        .accessibilityLabel(L10n.a11yRoomListFiltersButton)
        .accessibilityIdentifier(A11yIdentifiers.homeScreen.roomListFilters)
    }
}

// MARK: - Previews

struct SpaceTabBarView_Previews: PreviewProvider, TestablePreview {
    static let mediaProvider = MediaProviderMock(.init())

    static var previews: some View {
        VStack(spacing: 0) {
            SpaceTabBarView(filters: mockFilters,
                            selectedFilter: nil,
                            mediaProvider: mediaProvider,
                            isFiltering: false) { _ in } onFilterButtonTapped: {}

            Divider()

            SpaceTabBarView(filters: mockFilters,
                            selectedFilter: mockFilters.first,
                            mediaProvider: mediaProvider,
                            isFiltering: true) { _ in } onFilterButtonTapped: {}
        }
        .background(Color.compound.bgCanvasDefault)
    }

    static var mockFilters: [SpaceServiceFilter] {
        [SpaceServiceRoom].mockJoinedSpaces.prefix(4).map {
            SpaceServiceFilter(room: $0, level: 0, descendants: [])
        }
    }
}
```

Note the layout change: the previous single `ScrollView(.horizontal) { HStack(spacing: 8) { chips } }.padding(.horizontal, 16)` is now `HStack(spacing: 8) { ScrollView(.horizontal) { HStack(spacing: 8) { chips } } ; RoomFiltersButton(...) }` with padding moved to the outer `HStack`'s leading edge and the button's trailing edge — this keeps the button fixed regardless of how many spaces scroll past, per the design doc's requirement.

- [ ] **Step 2: Update the call site and remove the old chip row**

In `ElementX/Sources/Screens/HomeScreen/View/HomeScreenContent.swift`, replace the `topSection` computed property (currently lines 114-141):

```swift
    @ViewBuilder
    private var topSection: some View {
        // An empty VStack causes glitches within the room list
        if context.viewState.shouldShowSpaceTabBar || context.viewState.shouldShowBanner {
            VStack(spacing: 0) {
                if context.viewState.shouldShowSpaceTabBar {
                    SpaceTabBarView(filters: context.viewState.topLevelSpaceFilters,
                                    selectedFilter: context.viewState.selectedSpaceFilter,
                                    mediaProvider: context.mediaProvider,
                                    isFiltering: context.viewState.bindings.filtersState.isFiltering) { filter in
                        context.send(viewAction: .selectSpaceFilter(filter))
                    } onFilterButtonTapped: {
                        context.send(viewAction: .roomListFilters)
                    }
                    Divider()
                }

                if case let .show(state) = context.viewState.securityBannerMode {
                    HomeScreenRecoveryKeyConfirmationBanner(state: state, context: context)
                } else if context.viewState.shouldShowNewSoundBanner {
                    HomeScreenNewSoundBanner { context.send(viewAction: .dismissNewSoundBanner) }
                }
            }
            .background(Color.compound.bgCanvasDefault)
            .readHeight($topSectionHeight)
        }
    }
```

Note `shouldShowFilters` is dropped from the outer `if` condition and the `RoomListFiltersView(state: $context.filtersState)` line is deleted entirely — filtering is no longer a reason for `topSection` to render on its own; `shouldShowSpaceTabBar` and `shouldShowBanner` are the only remaining conditions (`shouldShowSpaceTabBar` itself still depends on `shouldShowFilters` internally per `HomeScreenModels.swift:125-127`, so this doesn't change when the space tab bar's row appears — only removes the now-deleted second row from the condition).

- [ ] **Step 3: Build**

Run: `swift build` (or `xcodebuild build -scheme ElementX`)
Expected: builds cleanly. If `shouldShowFilters` is now unused elsewhere and the compiler/SwiftLint flags it as dead code, leave it — it's still used by `shouldShowSpaceTabBar` and `shouldShowEmptyFilterState` (`HomeScreenModels.swift:153-161`), so it isn't actually dead.

- [ ] **Step 4: Regenerate Sourcery-derived test files**

Run: `sourcery --config Tools/Sourcery/PreviewTestsConfig.yml` then the `AccessibilityTests.yml`/`TestablePreviewsDictionary.yml` configs, same as Task 3 Step 2 — `SpaceTabBarView_Previews`' signature changed, so its generated snapshot test needs regenerating.

- [ ] **Step 5: Manually verify on device or simulator**

Run the app (Xcode Run, or `build_run_sim` if using Xcode MCP tooling) and confirm:
- The space chip row and the filter button appear on the same row, with the button fixed at the trailing edge even when scrolling the chips.
- Tapping the filter button opens the new sheet; toggling a filter (e.g. Unreads) immediately filters the room list underneath, live, without needing to close the sheet.
- Toggling an incompatible pair (e.g. People then Invites) hides the now-unavailable option from the sheet's list, matching the old chip row's behaviour.
- The badge dot appears on the button exactly when any filter is active, and disappears when cleared.

- [ ] **Step 6: Commit**

```bash
git add ElementX/Sources/Screens/HomeScreen/View/Filters/SpaceTabBarView.swift ElementX/Sources/Screens/HomeScreen/View/HomeScreenContent.swift PreviewTests/Sources/GeneratedPreviewTests.swift AccessibilityTests/Sources/*.swift ElementX/Sources/Other/TestablePreview/TestablePreviewsDictionary.swift
git commit -m "Collapse room list filters into a button on the space tab bar row"
```

## Self-Review Notes

- **Spec coverage:** every element of `docs/superpowers/specs/2026-07-03-room-filters-button-design.md` is covered — Task 1 (strings/a11y), Task 2 (multi-select toggle state + mutual exclusion, live not batched), Task 3 (sheet shell copied from `ChatsSpaceFiltersScreen`), Task 4 (wiring mirroring the `.spaceFilters` precedent exactly), Task 5 (fixed-button layout + removal of the old row + badge dot reusing the existing `overlayBadge` modifier, no new badge component).
- **Placeholder scan:** no TBD/TODO; the one open design choice flagged in the design doc (live vs batched filter application) is resolved explicitly in the Architecture section and Task 2's `.toggleFilter` sending `.filtersChanged` on every toggle, not just on close.
- **Type consistency:** `RoomListFiltersScreenViewModelAction`, `RoomListFiltersScreenViewState`, `RoomListFiltersScreenViewAction`, `RoomListFiltersScreenViewModel` are named identically across Tasks 2-4; `SpaceTabBarView`'s new `isFiltering`/`onFilterButtonTapped` parameters are threaded consistently through Task 5's `SpaceTabBarView.swift` and `HomeScreenContent.swift` call site.
- **Verified against real code, not guessed:** the `ChatsSpaceFiltersScreen` sheet-without-coordinator pattern, `StateStoreViewModelV2`'s optional `mediaProvider` parameter, the `BindableState` protocol's default `Void` bindings, the `RoomListFiltersState`/`RoomListFilter` API surface, the `overlayBadge` modifier signature, and the exact `.spaceFilters` wiring in `HomeScreenViewModel` were all read directly from the current source before writing this plan.
