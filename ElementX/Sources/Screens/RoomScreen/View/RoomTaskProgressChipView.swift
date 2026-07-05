//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

extension RoomTaskSummary {
    /// Whether the progress chip has anything to show for this summary.
    var showsProgressChip: Bool {
        !activeTasks.isEmpty || !pendingChoices.isEmpty
    }
}

/// A banner shown at the top of the timeline summarising the room's agent tasks.
/// A single active task shows its title and step progress, anything more shows
/// counts of active tasks and pending choices. Tapping opens the task panel.
struct RoomTaskProgressChipView: View {
    let summary: RoomTaskSummary
    let onTap: () -> Void

    var body: some View {
        if summary.showsProgressChip {
            Button(action: onTap) {
                HStack(spacing: 9) {
                    CompoundIcon(\.info, size: .medium, relativeTo: .compound.bodyMDSemibold)
                        .foregroundColor(Color.compound.iconSecondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.compound.bodyMDSemibold)
                            .foregroundColor(.compound.textPrimary)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.compound.bodySM)
                                .foregroundColor(.compound.textSecondary)
                        }
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

    /// The chip shows the task itself only when there's exactly one active task
    /// and nothing awaiting approval, otherwise it aggregates counts.
    private var singleTask: RoomTaskSummary.Task? {
        guard summary.activeTasks.count == 1, summary.pendingChoices.isEmpty else { return nil }
        return summary.activeTasks.first
    }

    private var title: String {
        if let singleTask {
            return singleTask.title.isEmpty ? UntranslatedL10n.screenRoomTimelineCanvasTaskBannerTitle : singleTask.title
        }

        var title = UntranslatedL10n.screenRoomTaskChipMulti(String(summary.activeTasks.count))
        if !summary.pendingChoices.isEmpty {
            title += UntranslatedL10n.screenRoomTaskChipPendingSuffix(String(summary.pendingChoices.count))
        }
        return title
    }

    private var subtitle: String? {
        guard let singleTask else { return nil }
        return "\(singleTask.doneStepCount)/\(singleTask.totalStepCount)"
    }
}

struct RoomTaskProgressChipView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        RoomTaskProgressChipView(summary: .init(activeTasks: [makeTask(id: "1", title: "Refactor auth module", doneStepCount: 3, totalStepCount: 7)])) { }
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Single task")

        RoomTaskProgressChipView(summary: .init(activeTasks: [makeTask(id: "1", title: "Refactor auth module", doneStepCount: 3, totalStepCount: 7),
                                                              makeTask(id: "2", title: "Write release notes", doneStepCount: 0, totalStepCount: 4)])) { }
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Multiple tasks")

        RoomTaskProgressChipView(summary: .init(activeTasks: [makeTask(id: "1", title: "Refactor auth module", doneStepCount: 3, totalStepCount: 7),
                                                              makeTask(id: "2", title: "Write release notes", doneStepCount: 0, totalStepCount: 4)],
                                                pendingChoices: [.init(eventID: "$choice-1", question: "Deploy to production?")])) { }
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Multiple tasks with pending")
    }

    static func makeTask(id: String, title: String, doneStepCount: Int, totalStepCount: Int) -> RoomTaskSummary.Task {
        .init(eventID: "$task-\(id)",
              taskID: id,
              title: title,
              isResolved: false,
              doneStepCount: doneStepCount,
              totalStepCount: totalStepCount,
              steps: [],
              threadRootEventID: nil,
              updatedAt: nil)
    }
}
