# Collapse Room List Filters into a Button on the Space Tab Bar

Status: approved
Date: 2026-07-03

## Problem

The Home screen currently stacks two always-visible horizontal rows above the room list: the space-switching chip row (`SpaceTabBarView`, added in commit `370f3ebf5`) and the room-list filter chip row (`RoomListFiltersView` — Unread/People/Rooms/Favourites/Invites/Low priority). Two full rows are cramped, especially on iPhone. This doc collapses the second row into a single button appended to the first row, opening a sheet for the same filter capability — no loss of functionality, less permanent screen space.

This is independent of the agent-turn message type work (`docs/superpowers/plans/2026-07-02-agent-turn-message-type.md`) — unrelated code path, both proceed separately.

## Approaches considered

- **Recommended: new sheet screen, button appended to the space tab bar row.** Reuses the existing `ChatsSpaceFiltersScreen` visual shell (`ElementNavigationStack`, drag indicator, scrollable list of rows) for consistency, but with toggle/multi-select rows instead of tap-to-dismiss, since `RoomListFilter` is multi-select with mutual exclusion (unlike the single-pick space filter).
- **Rejected: native SwiftUI `Menu` dropdown.** Cheaper to build, but less consistent with the existing sheet-based pattern already used for the analogous space-filter overflow case.
- **Rejected: inline collapsible chip row (expand/collapse in place).** Doesn't reclaim vertical space when expanded (the actual goal), and reuses less existing code than the new-sheet approach.

## Design

**Layout:** `SpaceTabBarView.body` currently is `ScrollView(.horizontal) { HStack { chips } }` — the whole chip row is the scroll content. Restructure to `HStack { ScrollView(.horizontal) { HStack { chips } } ; filterButton }` so the chips keep scrolling horizontally but the button is a fixed trailing element that never scrolls out of view, regardless of how many spaces the user has joined.

**Button:** `CompoundIcon(\.filter)` (icon confirmed present in the resolved `compound-design-tokens` package), with the existing `.overlayBadge(_:isBadged:)` modifier (`BadgeView.swift`, same pattern already used at `HomeScreen.swift:95`) showing a plain dot — not a numeric count — when `RoomListFiltersState.isFiltering` is true. No new badge component; reuses what's already in the codebase.

**New sheet screen** (name: `RoomListFiltersScreen`, new MVVM-C screen under `ElementX/Sources/Screens/`): visual shell copied from `ChatsSpaceFiltersScreen` (`ElementNavigationStack`, `.presentationDragIndicator(.visible)`, `ScrollView { LazyVStack { rows } }`). Each row renders one `RoomListFilter` case with a checkmark/toggle reflecting `RoomListFiltersState.isFilterActive(_:)`; tapping calls `activateFilter`/`deactivateFilter` exactly as `RoomListFiltersView` does today — same state object, same mutual-exclusion behavior via `incompatibleFilters` (an active filter's incompatible options are hidden/disabled, mirroring the existing `availableFilters` computation). The sheet does not auto-dismiss on toggle (multi-select must allow several taps); the toolbar keeps a "Clear" action (reusing the existing clear-all logic) and a close button, matching `ChatsSpaceFiltersScreen`'s toolbar convention.

**Removed:** the always-visible `RoomListFiltersView` mount in `HomeScreenContent.swift` (`topSection`, guarded by `shouldShowFilters`) is deleted entirely — filtering capability moves fully into the new sheet; nothing is removed from `RoomListFilterModels.swift` (the state/model layer is unchanged, only its presentation changes).

## Out of scope

- Any change to `RoomListFilter`'s six cases, their mutual-exclusion rules, or the underlying Rust filter mapping (`rustFilter`) — presentation-only change.
- Any change to `SpaceTabBarView`'s chip content itself (main-space chip + per-space chips) — only the row's trailing content changes.
- The pre-existing `ChatsSpaceFiltersScreen`/space-filter overflow sheet — untouched, just used as a visual reference.
