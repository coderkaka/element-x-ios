//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct ChatsSpaceFiltersScreen: View {
    @Bindable var context: ChatsSpaceFiltersScreenViewModel.Context

    var body: some View {
        ElementNavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ChatsSpaceFilterAllRow(isSelected: context.viewState.isAllFiltersSelected) {
                        context.send(viewAction: .confirm(nil))
                    }

                    ForEach(context.viewState.visibleFilters) { filter in
                        ChatsSpaceFilterCell(filter: filter,
                                             isSelected: filter.room.id == context.viewState.selectedSpaceFilterRoomID,
                                             mediaProvider: context.mediaProvider) { filter in
                            context.send(viewAction: .confirm(filter))
                        }
                        .contextMenu {
                            if filter.level == 0 {
                                reorderMenuItems(for: filter)
                            }
                        }
                    }
                }
                .searchable(text: $context.searchQuery, placement: .navigationBarDrawer)
                .focusSearchIfHardwareKeyboardAvailable()
                .compoundSearchField()
            }
            .toolbar { toolbar }
            .navigationTitle(L10n.screenRoomlistYourSpaces)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func reorderMenuItems(for filter: SpaceServiceFilter) -> some View {
        let order = context.viewState.topLevelFilterIDsInOrder
        let index = order.firstIndex(of: filter.room.id)

        Button(UntranslatedL10n.actionMoveLeft) {
            context.send(viewAction: .reorder(roomID: filter.room.id, direction: .left))
        }
        .disabled(index == nil || index == 0)

        Button(UntranslatedL10n.actionMoveRight) {
            context.send(viewAction: .reorder(roomID: filter.room.id, direction: .right))
        }
        .disabled(index == nil || index == order.count - 1)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            manageButton
        }

        ToolbarItem(placement: .primaryAction) {
            ToolbarButton(role: .close) {
                context.send(viewAction: .cancel)
            }
        }
    }

    private var manageButton: some View {
        Button {
            context.send(viewAction: .manageSpaces)
        } label: {
            CompoundIcon(\.settings, size: .small, relativeTo: .compound.bodyMD)
                .foregroundColor(.compound.iconSecondary)
                .overlayBadge(10, isBadged: context.viewState.hasPendingSpaceInvites)
        }
        .accessibilityLabel(UntranslatedL10n.actionManageSpaces)
    }
}

/// The pinned "全部" row — clears the 道 filter (fix-spacebar3 contract C).
private struct ChatsSpaceFilterAllRow: View {
    let isSelected: Bool
    let action: () -> Void

    private let verticalInsets = 12.0
    private let horizontalInsets = 16.0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12.0) {
                Text(UntranslatedL10n.screenHomeSpaceAll)
                    .font(.compound.bodyLG)
                    .foregroundColor(.compound.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    CompoundIcon(\.check, size: .small, relativeTo: .compound.bodyLG)
                        .foregroundColor(.compound.iconAccentTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, verticalInsets)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.compound.borderDisabled)
                    .frame(height: 1 / UIScreen.main.scale)
            }
        }
        .padding(.horizontal, horizontalInsets)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

struct ChatsSpaceFiltersScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    static let selectedViewModel = makeViewModel(selectedSpaceFilterRoomID: "space1")
    static let invitesPendingViewModel = makeViewModel(hasPendingSpaceInvites: true)

    static var previews: some View {
        ChatsSpaceFiltersScreen(context: viewModel.context)
            .previewDisplayName("All selected")

        ChatsSpaceFiltersScreen(context: selectedViewModel.context)
            .previewDisplayName("Space selected")

        ChatsSpaceFiltersScreen(context: invitesPendingViewModel.context)
            .previewDisplayName("Pending space invite")
    }

    static func makeViewModel(selectedSpaceFilterRoomID: String? = nil,
                              hasPendingSpaceInvites: Bool = false) -> ChatsSpaceFiltersScreenViewModel {
        let appSettings: AppSettings = .volatile()
        appSettings.selectedSpaceFilterRoomID = selectedSpaceFilterRoomID
        return ChatsSpaceFiltersScreenViewModel(spaceService: SpaceServiceProxyMock(.populated),
                                                appSettings: appSettings,
                                                hasPendingSpaceInvites: hasPendingSpaceInvites,
                                                mediaProvider: MediaProviderMock(.init()))
    }
}
