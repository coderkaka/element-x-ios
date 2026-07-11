# Room Filters Button Icon & Badge Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swap the room-list filters button's icon (`\.filter` → `\.listBulleted`) and replace its plain-dot "any filter active" badge with a numeric count badge, so it's visually distinct from the pre-existing `SpaceFiltersButton` toolbar icon which also uses `\.filter`.

**Architecture:** Extend `ElementX/Sources/Other/SwiftUI/Views/BadgeView.swift` with a second, parallel view/modifier/extension trio (`CountBadgeView`/`CountBadgeViewModifier`/`overlayCountBadge(_:count:)`) that mirrors the existing dot-badge pattern (`BadgeView`/`BadgeViewModifier`/`overlayBadge(_:isBadged:)`) but renders a digit instead of a plain circle. `SpaceTabBarView`'s private `RoomFiltersButton` swaps its icon key path and its badge call; its public `isFiltering: Bool` parameter becomes `activeFilterCount: Int` so the button (and its caller) can supply the actual count, not just a boolean.

**Tech Stack:** Swift 6.2, SwiftUI, Compound (`CompoundIcon`, `.compound.iconCriticalPrimary`, `.compound.textOnSolidPrimary`, `.compound.bodyXSSemibold`), Sourcery-generated `TestablePreview` snapshot/accessibility tests.

## Global Constraints

- This Linux machine has no local Swift/Xcode toolchain — every build/test runs over SSH on a remote Mac (`ssh -i ~/.ssh/id_ed25519_kaka zhangqiong@mac-mini.tail2edbaa.ts.net "cd ~/Code/element-x-ios && <command>"`). Implement and commit locally on Linux, push to `coderkaka feature/space-tab-bar`, then SSH to the Mac to pull, build, and test.
- New files must be registered in `ElementX.xcodeproj/project.pbxproj` by running `/opt/homebrew/bin/xcodegen` on the Mac after pulling, and the regenerated `project.pbxproj` (if it changes) must be pulled back to this Linux repo and committed — do not leave it as Mac-local-only state. This task modifies an existing file (`BadgeView.swift`) and adds no new files, so a registration gap is unlikely, but verify anyway before reporting done.
- `SpaceTabBarView_Previews` is a `PreviewProvider, TestablePreview` — its generated snapshot/accessibility test files (`PreviewTests/Sources/GeneratedPreviewTests.swift`, `AccessibilityTests/Sources/GeneratedAccessibilityTests.swift`, `ElementX/Sources/Other/TestablePreview/TestablePreviewsDictionary.swift`) are keyed off the type name, not its call signature, so they do NOT need Sourcery regeneration for this task (the type name `SpaceTabBarView_Previews` isn't changing) — only the snapshot PNG references need re-recording since the rendered pixels change.
- `Untranslated.strings` entries generate into a separate `UntranslatedL10n` enum (`ElementX/Sources/Generated/Strings+Untranslated.swift`), not the main `L10n` enum — not relevant to this plan (no new strings), noted here only because it has bitten prior tasks in this session and is worth remembering if scope changes.
- Follow Swift API Design Guidelines; no comments restating what the code already says.

---

## Task 1: Add a numeric count badge and wire it into `RoomFiltersButton`

**Files:**
- Modify: `ElementX/Sources/Other/SwiftUI/Views/BadgeView.swift`
- Modify: `ElementX/Sources/Screens/HomeScreen/View/Filters/SpaceTabBarView.swift`
- Modify: `ElementX/Sources/Screens/HomeScreen/View/HomeScreenContent.swift:120-123`

**Interfaces:**
- Consumes: `RoomListFiltersState.activeFilters: OrderedSet<RoomListFilter>` (existing, `RoomListFilterModels.swift:84`, publicly readable via `private(set)`).
- Produces: `View.overlayCountBadge(_ size: Double, count: Int) -> some View` (new, mirrors existing `overlayBadge(_:isBadged:)`); `SpaceTabBarView.activeFilterCount: Int` (replaces the old `isFiltering: Bool` parameter).

This task has no unit test of its own — pure SwiftUI view code, covered by the existing `SpaceTabBarView_Previews` → Sourcery-generated snapshot/accessibility tests (already exercises both "0 active filters" and "some active filters" states via its two preview cases).

- [ ] **Step 1: Add the numeric count badge to `BadgeView.swift`**

Replace the full contents of `ElementX/Sources/Other/SwiftUI/Views/BadgeView.swift` with:

```swift
//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct BadgeView: View {
    let size: Double
    
    var body: some View {
        Circle()
            .fill(.compound.iconCriticalPrimary)
            .frame(width: size, height: size)
    }
}

struct BadgeViewModifier: ViewModifier {
    let size: Double
    
    func body(content: Content) -> some View {
        content.mask {
            Rectangle()
                .fill(.white)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.black)
                        .frame(width: maskSize, height: maskSize)
                        .offset(maskOffset)
                }
                .compositingGroup()
                .luminanceToAlpha()
        }
        .overlay(alignment: .topTrailing) {
            BadgeView(size: size)
        }
    }
    
    private var maskSize: Double {
        size * 1.25
    }
    
    private var maskOffset: CGSize {
        .init(width: (maskSize - size) / 2, height: -(maskSize - size) / 2)
    }
}

struct CountBadgeView: View {
    let count: Int
    let size: Double
    
    var body: some View {
        Circle()
            .fill(.compound.iconCriticalPrimary)
            .frame(width: size, height: size)
            .overlay {
                Text(String(count))
                    .font(.compound.bodyXSSemibold)
                    .foregroundStyle(.compound.textOnSolidPrimary)
                    .dynamicTypeSize(.large)
            }
    }
}

struct CountBadgeViewModifier: ViewModifier {
    let count: Int
    let size: Double
    
    func body(content: Content) -> some View {
        content.mask {
            Rectangle()
                .fill(.white)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.black)
                        .frame(width: maskSize, height: maskSize)
                        .offset(maskOffset)
                }
                .compositingGroup()
                .luminanceToAlpha()
        }
        .overlay(alignment: .topTrailing) {
            CountBadgeView(count: count, size: size)
        }
    }
    
    private var maskSize: Double {
        size * 1.25
    }
    
    private var maskOffset: CGSize {
        .init(width: (maskSize - size) / 2, height: -(maskSize - size) / 2)
    }
}

extension View {
    @ViewBuilder
    func overlayBadge(_ size: Double, isBadged: Bool = true) -> some View {
        if isBadged {
            modifier(BadgeViewModifier(size: size))
        } else {
            self
        }
    }
    
    @ViewBuilder
    func overlayCountBadge(_ size: Double, count: Int) -> some View {
        if count > 0 {
            modifier(CountBadgeViewModifier(count: count, size: size))
        } else {
            self
        }
    }
}

struct BadgeView_Previews: PreviewProvider {
    static let circleGradient = LinearGradient(colors: [.green, .orange],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing)
    static let screenGradient = LinearGradient(colors: [.pink, .blue],
                                               startPoint: .top,
                                               endPoint: .bottom)
    static var previews: some View {
        Circle()
            .fill(circleGradient)
            .saturation(2.0)
            .frame(width: 100, height: 100)
            .overlayBadge(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { screenGradient.opacity(0.3).ignoresSafeArea() }
    }
}
```

Note: `overlayBadge`/`BadgeView`/`BadgeViewModifier` are unchanged — only `CountBadgeView`, `CountBadgeViewModifier`, and the new `overlayCountBadge(_:count:)` extension method are additions. `BadgeView_Previews` is unchanged (it demonstrates the dot badge; no preview is required for `CountBadgeView` since `SpaceTabBarView_Previews`, updated in Step 2, exercises it in context).

- [ ] **Step 2: Update `RoomFiltersButton` and `SpaceTabBarView` in `SpaceTabBarView.swift`**

In `ElementX/Sources/Screens/HomeScreen/View/Filters/SpaceTabBarView.swift`, replace the full file contents with:

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
    let activeFilterCount: Int
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
            
            RoomFiltersButton(activeFilterCount: activeFilterCount, action: onFilterButtonTapped)
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
    let activeFilterCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            CompoundIcon(\.listBulleted, size: .small, relativeTo: .compound.bodyLG)
                .foregroundStyle(.compound.iconPrimary)
                .padding(7)
                .background(.compound.bgSubtlePrimary, in: .circle)
                .overlayCountBadge(16, count: activeFilterCount)
        }
        .accessibilityLabel(UntranslatedL10n.a11yRoomListFiltersButton)
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
                            activeFilterCount: 0) { _ in } onFilterButtonTapped: { }
            
            Divider()
            
            SpaceTabBarView(filters: mockFilters,
                            selectedFilter: mockFilters.first,
                            mediaProvider: mediaProvider,
                            activeFilterCount: 2) { _ in } onFilterButtonTapped: { }
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

Changes from the current file: `isFiltering: Bool` → `activeFilterCount: Int` on both `SpaceTabBarView` and the private `RoomFiltersButton`; `RoomFiltersButton`'s icon key path `\.filter` → `\.listBulleted`; its badge call `.overlayBadge(8, isBadged: isFiltering)` → `.overlayCountBadge(16, count: activeFilterCount)`; the two preview cases pass `activeFilterCount: 0` and `activeFilterCount: 2` (2, not a bare truthy `1`, so the recorded snapshot visibly shows a 2-digit-capable badge rendering correctly, not just "any nonzero digit").

- [ ] **Step 3: Update the call site in `HomeScreenContent.swift`**

In `ElementX/Sources/Screens/HomeScreen/View/HomeScreenContent.swift`, the `topSection` computed property currently reads (lines 120-123):

```swift
                    SpaceTabBarView(filters: context.viewState.topLevelSpaceFilters,
                                    selectedFilter: context.viewState.selectedSpaceFilter,
                                    mediaProvider: context.mediaProvider,
                                    isFiltering: context.viewState.bindings.filtersState.isFiltering) { filter in
```

Change the fourth argument line to:

```swift
                    SpaceTabBarView(filters: context.viewState.topLevelSpaceFilters,
                                    selectedFilter: context.viewState.selectedSpaceFilter,
                                    mediaProvider: context.mediaProvider,
                                    activeFilterCount: context.viewState.bindings.filtersState.activeFilters.count) { filter in
```

Only that one argument label/expression changes; the trailing closures (`{ filter in ... } onFilterButtonTapped: { ... }`) and everything else in `topSection` stay exactly as they are.

- [ ] **Step 4: Build the whole scheme**

Run over SSH on the Mac (from `~/Code/element-x-ios`, after `git pull`):

```
xcodebuild build -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>'
```

(Find the current simulator id via `xcrun simctl list devices | grep -i 'iPhone 17 ('` if the previously-used id is stale.)

Expected: `** BUILD SUCCEEDED **`, zero errors or warnings in the two changed files.

- [ ] **Step 5: Re-record the `spaceTabBarView` snapshot test**

The rendered pixels changed (new icon, new badge shape/content), so the existing reference snapshots are now stale and must be re-recorded, not just re-run.

Run over SSH on the Mac: toggle `RECORD_FAILURES` to `enabled: true` in `PreviewTests/SupportingFiles/PreviewTests.xctestplan`, then:

```
xcodebuild test -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>' -only-testing:'PreviewTests/PreviewTests/spaceTabBarView()'
```

Expected: PASS (records new reference PNGs under `PreviewTests/Sources/__Snapshots__/PreviewTests/spaceTabBarView.*`). Afterward, toggle `RECORD_FAILURES` back to `enabled: false` and run `git checkout -- PreviewTests/SupportingFiles/PreviewTests.xctestplan` on the Mac so that toggle is never committed.

Then re-run the same test once more without `RECORD_FAILURES` to confirm the newly recorded references are stable:

```
xcodebuild test -project ElementX.xcodeproj -scheme ElementX -destination 'platform=iOS Simulator,id=<current simulator id>' -only-testing:'PreviewTests/PreviewTests/spaceTabBarView()'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ElementX/Sources/Other/SwiftUI/Views/BadgeView.swift \
        ElementX/Sources/Screens/HomeScreen/View/Filters/SpaceTabBarView.swift \
        ElementX/Sources/Screens/HomeScreen/View/HomeScreenContent.swift \
        PreviewTests/Sources/__Snapshots__/PreviewTests/spaceTabBarView.*
git commit -m "Redesign room filters button: listBulleted icon and numeric badge"
```

---

## Self-Review Notes

- **Spec coverage:** every requirement in `docs/superpowers/specs/2026-07-04-room-filters-button-icon-design.md` is covered — icon swap (Step 2), numeric badge replacing the dot (Steps 1-2), count sourced from `activeFilters.count` (Step 3), 0-hidden/1+-shown behavior (`overlayCountBadge`'s `count > 0` guard, Step 1), container shape/size/position unchanged (Step 2's diff touches only the icon key path, badge call, and parameter rename — nothing else in `RoomFiltersButton`/`SpaceTabBarView`'s layout), `SpaceFiltersButton` untouched (not referenced anywhere in this plan), existing preview cases reused rather than adding new ones (Step 2 keeps exactly two preview cases, just changes their argument values).
- **Placeholder scan:** no TBD/TODO; every step shows complete, copy-pasteable code or exact commands.
- **Type consistency:** `activeFilterCount: Int` is named and typed identically across `SpaceTabBarView`, `RoomFiltersButton`, and the `HomeScreenContent.swift` call site (Steps 2-3). `overlayCountBadge(_:count:)`'s signature in `BadgeView.swift` (Step 1) matches its call site in `RoomFiltersButton` (Step 2) exactly.
- **Verified against real code, not guessed:** `RoomListFiltersState.activeFilters`'s existing type/visibility (`OrderedSet<RoomListFilter>`, `private(set)`, so `.count` is readable) was read directly from `RoomListFilterModels.swift:84` before writing this plan; `listBulleted` was confirmed present in the resolved `compound-design-tokens` package's `CompoundIcons.swift` on the build Mac (not the design doc's inference alone); `Font.compound.bodyXSSemibold` was confirmed to exist in `CompoundFonts.swift:20` as the smallest available Compound font token; the exact current file contents of `BadgeView.swift`, `SpaceTabBarView.swift`, and the `HomeScreenContent.swift` call site (lines 120-123) were read directly, not assumed, before drafting the diffs above.
