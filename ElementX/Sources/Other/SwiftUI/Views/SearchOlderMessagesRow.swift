//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// A row inviting the user to index another (large) batch of a room's older history for search —
/// shared between `SearchScreen` and `HomeScreen`'s inline search.
struct SearchOlderMessagesRow: View {
    let isSearching: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isSearching {
                    ProgressView()
                    Text(UntranslatedL10n.screenSearchSearchingOlderMessages)
                } else {
                    Text(UntranslatedL10n.screenSearchSearchOlderMessagesAction)
                }
            }
            .foregroundStyle(.compound.textActionPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .disabled(isSearching)
        .listRowInsets(.init())
        .listRowSeparator(.hidden)
    }
}

// MARK: - Previews

struct SearchOlderMessagesRow_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        List {
            SearchOlderMessagesRow(isSearching: false) { }
            SearchOlderMessagesRow(isSearching: true) { }
        }
        .compoundList(.plain)
    }
}
