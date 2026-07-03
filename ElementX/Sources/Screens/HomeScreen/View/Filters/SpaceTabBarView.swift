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
