//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// A single message search result row — shared between `SearchScreen` and `HomeScreen`'s
/// inline search so both surfaces render results identically.
struct MessageSearchResultCell: View {
    let result: MessageSearchResultItem
    let mediaProvider: MediaProviderProtocol?
    let action: () -> Void
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                avatar
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(result.sender.disambiguatedDisplayName ?? result.sender.id)
                            .font(.compound.bodyMDSemibold)
                            .foregroundStyle(.compound.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(result.timestamp.formattedMinimal())
                            .font(.compound.bodyXS)
                            .foregroundStyle(.compound.textSecondary)
                    }
                    
                    if let body = result.body {
                        Text(body)
                            .font(.compound.bodyMD)
                            .foregroundStyle(.compound.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(MessageSearchResultCellButtonStyle())
        .listRowInsets(.init())
        .listRowSeparator(.hidden)
        .rowDivider()
    }
    
    @ViewBuilder
    private var avatar: some View {
        if dynamicTypeSize < .accessibility3 {
            LoadableAvatarImage(url: result.sender.avatarURL,
                                name: result.sender.disambiguatedDisplayName,
                                contentID: result.sender.id,
                                avatarSize: .user(on: .timeline),
                                mediaProvider: mediaProvider)
                .dynamicTypeSize(dynamicTypeSize < .accessibility1 ? dynamicTypeSize : .accessibility1)
                .accessibilityHidden(true)
        }
    }
}

private struct MessageSearchResultCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.compound.bgSubtleSecondary : Color.compound.bgCanvasDefault)
            .contentShape(Rectangle())
    }
}

// MARK: - Previews

struct MessageSearchResultCell_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        List {
            MessageSearchResultCell(result: .init(eventID: "$1",
                                                  roomID: "!room1:matrix.org",
                                                  sender: TimelineItemSender(id: "@alice:matrix.org", displayName: "Alice"),
                                                  body: AttributedString("Hey, did you see the new design doc? I left some comments."),
                                                  timestamp: .now),
                                    mediaProvider: MediaProviderMock(.init())) { }
        }
        .compoundList(.plain)
    }
}
