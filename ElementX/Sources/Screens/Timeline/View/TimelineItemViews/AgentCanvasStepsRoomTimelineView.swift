//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct AgentCanvasStepsRoomTimelineView: View {
    let timelineItem: AgentCanvasStepsRoomTimelineItem
    
    private var content: AgentCanvasStepsRoomTimelineItemContent {
        timelineItem.content
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            HStack(spacing: 4) {
                CompoundIcon(\.info, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundColor(.compound.iconSecondary)
                Text(content.title.isEmpty ? content.body : content.title)
                    .font(.compound.bodyMD)
                    .foregroundColor(.compound.textPrimary)
            }
        }
    }
}

struct AgentCanvasStepsRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock
    
    static var previews: some View {
        PreviewScrollView {
            VStack(spacing: 8) {
                states
            }
        }
        .previewLayout(.sizeThatFits)
        .environmentObject(viewModel.context)
    }
    
    @ViewBuilder
    static var states: some View {
        AgentCanvasStepsRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                             timestamp: .mock,
                                                             isOutgoing: false,
                                                             isEditable: false,
                                                             canBeRepliedTo: true,
                                                             sender: .init(id: "@agent:example.com"),
                                                             content: .init(body: "Task: Refactor auth module",
                                                                            taskID: "task-1234",
                                                                            title: "Refactor auth module",
                                                                            isResolved: false,
                                                                            steps: [CanvasStep(id: "s1", label: "Read existing code", status: .done),
                                                                                    CanvasStep(id: "s2", label: "Wait for approval", status: .inProgress)])))
        
        AgentCanvasStepsRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                             timestamp: .mock,
                                                             isOutgoing: false,
                                                             isEditable: false,
                                                             canBeRepliedTo: true,
                                                             sender: .init(id: "@agent:example.com"),
                                                             content: .init(body: "Task: Refactor auth module",
                                                                            taskID: "task-1234",
                                                                            title: "Refactor auth module",
                                                                            isResolved: true,
                                                                            steps: [CanvasStep(id: "s1", label: "Read existing code", status: .done),
                                                                                    CanvasStep(id: "s2", label: "Run tests", status: .done)])))
    }
}
