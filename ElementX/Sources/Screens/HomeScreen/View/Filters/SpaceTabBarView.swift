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
    let hasPendingSpaceInvites: Bool
    let terminology: AppTerminology
    let mediaProvider: MediaProviderProtocol!
    let action: (SpaceServiceFilter?) -> Void
    let onManageTapped: () -> Void
    let onReorder: (String, MoveDirection) -> Void
    
    /// Backs the selected chip's sliding highlight (fix-kanban2 contract C) — one shared
    /// namespace so `matchedGeometryEffect` can animate the highlight moving between whichever
    /// two chips are the old/new selection, entirely internal so callers stay unaware of it.
    @Namespace private var selectionNamespace
    private static let selectionGeometryID = "selectedSpaceChip"
    
    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    SpaceTabChipView(name: UntranslatedL10n.screenHomeSpaceAll,
                                     avatar: nil,
                                     isSelected: selectedFilter == nil,
                                     mediaProvider: mediaProvider,
                                     selectionNamespace: selectionNamespace,
                                     selectionGeometryID: Self.selectionGeometryID) {
                        selectFilter(nil)
                    }
                    .overlayBadge(10, isBadged: hasPendingSpaceInvites)
                    
                    ForEach(Array(filters.enumerated()), id: \.element.id) { index, filter in
                        SpaceTabChipView(name: filter.room.name,
                                         avatar: filter.room.avatar,
                                         isSelected: selectedFilter == filter,
                                         mediaProvider: mediaProvider,
                                         selectionNamespace: selectionNamespace,
                                         selectionGeometryID: Self.selectionGeometryID) {
                            selectFilter(filter)
                        }
                        .contextMenu {
                            Button(UntranslatedL10n.actionMoveLeft) {
                                onReorder(filter.room.id, .left)
                            }
                            .disabled(index == 0)
                            
                            Button(UntranslatedL10n.actionMoveRight) {
                                onReorder(filter.room.id, .right)
                            }
                            .disabled(index == filters.count - 1)
                        }
                    }
                }
                .padding(.vertical, 12)
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: selectedFilter)
            }
            .scrollIndicators(.hidden)
            
            Button(action: onManageTapped) {
                CompoundIcon(\.settings, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundColor(.compound.iconSecondary)
            }
            .accessibilityLabel(terminology.manageSpaces)
            .padding(.trailing, 16)
        }
        .padding(.leading, 16)
    }
    
    /// Light tap feedback on an actual selection change — follows `TimelineScrollButton`'s
    /// existing `UIImpactFeedbackGenerator` precedent elsewhere in the codebase (no
    /// `sensoryFeedback` usage to match instead). Skipped on a no-op tap of the already-selected chip.
    private func selectFilter(_ filter: SpaceServiceFilter?) {
        guard filter != selectedFilter else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        action(filter)
    }
}

private struct SpaceTabChipView: View {
    let name: String
    let avatar: RoomAvatar?
    let isSelected: Bool
    let mediaProvider: MediaProviderProtocol!
    let selectionNamespace: Namespace.ID
    let selectionGeometryID: String
    let action: () -> Void
    
    private var strokeColor: Color {
        isSelected ? .compound.bgActionPrimaryRest : .compound.borderInteractiveSecondary
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
            .background {
                if isSelected {
                    shape.fill(Color.compound.bgActionPrimaryRest)
                        .matchedGeometryEffect(id: selectionGeometryID, in: selectionNamespace)
                } else {
                    shape.fill(Color.compound.bgCanvasDefault)
                }
            }
            .overlay {
                shape
                    .inset(by: 0.5)
                    .stroke(strokeColor)
            }
            .drawingGroup()
        }
    }
}

// MARK: - Previews

struct SpaceTabBarView_Previews: PreviewProvider, TestablePreview {
    static let mediaProvider = MediaProviderMock(.init())
    
    static var previews: some View {
        VStack(spacing: 0) {
            SpaceTabBarView(filters: mockFilters,
                            selectedFilter: nil,
                            hasPendingSpaceInvites: false,
                            terminology: .init(scenario: .imperial),
                            mediaProvider: mediaProvider) { _ in } onManageTapped: { } onReorder: { _, _ in }
            
            Divider()
            
            SpaceTabBarView(filters: mockFilters,
                            selectedFilter: mockFilters.first,
                            hasPendingSpaceInvites: false,
                            terminology: .init(scenario: .imperial),
                            mediaProvider: mediaProvider) { _ in } onManageTapped: { } onReorder: { _, _ in }
            
            Divider()
            
            // The sliding highlight lands on the second chip rather than the first — a quick
            // visual check that `matchedGeometryEffect` picks up whichever chip is selected, not
            // just always the leading one (fix-kanban2 contract C).
            SpaceTabBarView(filters: mockFilters,
                            selectedFilter: mockFilters[1],
                            hasPendingSpaceInvites: false,
                            terminology: .init(scenario: .imperial),
                            mediaProvider: mediaProvider) { _ in } onManageTapped: { } onReorder: { _, _ in }
            
            Divider()
            
            SpaceTabBarView(filters: [],
                            selectedFilter: nil,
                            hasPendingSpaceInvites: false,
                            terminology: .init(scenario: .imperial),
                            mediaProvider: mediaProvider) { _ in } onManageTapped: { } onReorder: { _, _ in }
            
            Divider()
            
            SpaceTabBarView(filters: mockFilters,
                            selectedFilter: nil,
                            hasPendingSpaceInvites: true,
                            terminology: .init(scenario: .imperial),
                            mediaProvider: mediaProvider) { _ in } onManageTapped: { } onReorder: { _, _ in }
        }
        .background(Color.compound.bgCanvasDefault)
    }
    
    static var mockFilters: [SpaceServiceFilter] {
        [SpaceServiceRoom].mockJoinedSpaces.prefix(4).map {
            SpaceServiceFilter(room: $0, level: 0, descendants: [])
        }
    }
}
