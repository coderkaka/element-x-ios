//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// A full-width strip shown above the room list summarising 请旨待批 (pending agent choices)
/// across every room. Tapping opens the single pending room directly, or a picker sheet when
/// there's more than one — see `HomeScreenViewModel.process(viewAction:)`.
struct PendingChoicesStripView: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 9) {
                CompoundIcon(\.error, size: .medium, relativeTo: .compound.bodyMDSemibold)
                    .foregroundColor(.compound.iconCriticalPrimary)
                    .accessibilityHidden(true)
                Text(UntranslatedL10n.screenHomePendingChoicesStrip(String(count)))
                    .font(.compound.bodyMDSemibold)
                    .foregroundColor(.compound.textPrimary)
                Spacer()
                CompoundIcon(\.chevronRight, size: .small, relativeTo: .compound.bodySM)
                    .foregroundColor(.compound.iconTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 15)
        .background(Color.compound.bgCanvasDefault)
    }
}

struct PendingChoicesStripView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        PendingChoicesStripView(count: 1) { }
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Single pending")

        PendingChoicesStripView(count: 3) { }
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Multiple pending")
    }
}
