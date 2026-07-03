# Room Filters Button: Icon & Badge Redesign

Status: approved
Date: 2026-07-04

## Problem

The room-list filters button shipped in `docs/superpowers/specs/2026-07-03-room-filters-button-design.md` (`RoomFiltersButton` in `SpaceTabBarView.swift`) reuses the exact same `\.filter` (funnel) glyph as the pre-existing `SpaceFiltersButton` in `HomeScreen.swift`'s navigation bar toolbar. Both buttons are visible simultaneously whenever the account has any Spaces — `SpaceFiltersButton` is shown when `shouldShowSpaceFilters` (`!filters.isEmpty`), and `RoomFiltersButton` lives inside `SpaceTabBarView`, shown when `shouldShowSpaceTabBar` (`!topLevelSpaceFilters.isEmpty && shouldShowFilters`) — both gated on the same "has Spaces" condition. Two buttons with an identical icon but different meanings (space hierarchy picker vs. room-list filter toggles), visible together on one screen, reads as unpolished and confusing.

## Decision

Change only `RoomFiltersButton` (the new button, `SpaceTabBarView.swift`). `SpaceFiltersButton` (the pre-existing toolbar button) is untouched — it's a separate, non-redundant feature (full space hierarchy including nested sub-spaces, vs. `SpaceTabBarView`'s top-level-only chip row).

**Icon:** swap `CompoundIcon(\.filter, ...)` → `CompoundIcon(\.listBulleted, ...)`. `listBulleted` is a real, existing icon in Compound's icon set (verified against `CompoundIcons.swift` in the resolved `compound-design-tokens` package — not a placeholder or invented name). Visually and semantically distinct from the toolbar's funnel: the room filters sheet is a "toggle a set of switches" interaction (per the original room-filters-button design), which `listBulleted` (a checklist glyph) represents more accurately than a funnel ("filter results down").

**Badge:** replace the existing plain-dot badge (`.overlayBadge(8, isBadged: isFiltering)`, from `BadgeView.swift` — a fixed-size solid circle, no text support) with a small numeric badge showing the count of active filters (`RoomListFiltersState.activeFilters.count`, a `private(set)` `OrderedSet<RoomListFilter>` — publicly readable). Hidden when the count is 0 (same visibility condition as today's `isFiltering`), shown with the digit when 1 or more (max is 6, since there are only 6 `RoomListFilter` cases — always a single digit, no truncation/overflow handling needed).

No existing numeric-badge component exists in the codebase to reuse (`BadgeView`/`overlayBadge` is dot-only; the tab-bar `.badge(_:)` usage in `NavigationTabCoordinator.swift` is a SwiftUI `TabView`-native API, not applicable to an arbitrary button). This requires a new small view.

**Unchanged:** button container shape/size/position (circle, `.compound.bgSubtlePrimary` background, fixed at the trailing edge of `SpaceTabBarView`'s row), accessibility label/identifier, all interaction/wiring from the room-filters-button plan (Tasks 1-5).

## Rejected alternatives

- **Keep `\.filter` icon, just swap dot → numeric badge.** Doesn't solve the actual icon collision with the toolbar button — the two funnels would still look identical at a glance, just with different badge styles.
- **Keep `\.filter` icon, tint the whole button on active state instead of a badge.** Considered and rejected: the accent-color tint would visually compete with the already-selected space chip's accent-color highlight in the same row, creating a *new* ambiguity ("is this button showing 'selected space' or 'filters active'?") in exchange for solving the old one.

## Components

**New: numeric count badge view** (exact file path/name is an implementation detail for the plan — a small, single-purpose `View` taking an `Int` and rendering a circle + centered digit, following `BadgeView.swift`'s existing structure/coloring as the pattern to extend, not replace).

**Modified: `RoomFiltersButton`** (private struct inside `SpaceTabBarView.swift`) — icon key path change, badge modifier swap from the boolean `isFiltering` overlay to the new numeric badge fed by `activeFilters.count`.

## Testing

Existing `spaceTabBarView` snapshot test (`SpaceTabBarView_Previews`, `TestablePreview`) already covers both the "no filters" and "some filters active" states via its two preview cases — re-recording those snapshots after this change is sufficient visual regression coverage. No new preview cases needed; the existing ones already exercise badge-hidden and badge-shown. If the new count badge view is extracted as its own reusable type, it can optionally get its own minimal preview, but that's not required for this scope.
