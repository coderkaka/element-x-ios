//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// A banner shown at the top of the timeline while an agent's `io.element.agent.canvas.steps`
/// task is in progress, letting the user jump to the full step tracker.
struct CanvasTaskBannerView: View {
    let title: String
    let onMainButtonTap: () -> Void
    
    var body: some View {
        Button(action: onMainButtonTap) {
            HStack(spacing: 9) {
                CompoundIcon(\.info, size: .medium, relativeTo: .compound.bodyMDSemibold)
                    .foregroundColor(Color.compound.iconSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title.isEmpty ? UntranslatedL10n.screenRoomTimelineCanvasTaskBannerTitle : title)
                        .font(.compound.bodyMDSemibold)
                        .foregroundColor(.compound.textPrimary)
                        .lineLimit(1)
                    Text(UntranslatedL10n.screenRoomTimelineCanvasTaskBannerAction)
                        .font(.compound.bodySM)
                        .foregroundColor(.compound.textSecondary)
                }
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

struct CanvasTaskBannerView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        CanvasTaskBannerView(title: "Refactor auth module") { }
            .previewLayout(.sizeThatFits)
    }
}
