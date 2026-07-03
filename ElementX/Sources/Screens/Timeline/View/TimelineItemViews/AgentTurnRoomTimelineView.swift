//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct AgentTurnRoomTimelineView: View {
    enum AccessibilityFocus {
        case disclosure
        case toolCalls
    }
    
    let timelineItem: AgentTurnRoomTimelineItem
    
    @State private var isToolCallsExpanded = false
    @AccessibilityFocusState private var accessibilityFocusState: AccessibilityFocus?
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            VStack(alignment: .leading, spacing: 8) {
                if !timelineItem.content.toolCalls.isEmpty {
                    toolCallsDisclosure
                }
                
                Text(timelineItem.content.body)
                    .font(.compound.bodyMD)
                    .foregroundColor(.compound.textPrimary)
            }
        }
    }
    
    private var toolCallsDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withElementAnimation {
                    isToolCallsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(UntranslatedL10n.screenRoomTimelineAgentTurnToolCallsCount(timelineItem.content.toolCalls.count))
                        .font(.compound.bodySM)
                    CompoundIcon(\.chevronRight, size: .small, relativeTo: .compound.bodySM)
                        .accessibilityLabel(isToolCallsExpanded ? UntranslatedL10n.a11yCollapseToolCalls : UntranslatedL10n.a11yExpandToolCalls)
                        .rotationEffect(.degrees(isToolCallsExpanded ? 90 : 0))
                        .animation(.elementDefault, value: isToolCallsExpanded)
                }
                .foregroundColor(.compound.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityFocused($accessibilityFocusState, equals: .disclosure)
            
            if isToolCallsExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(timelineItem.content.toolCalls.enumerated()), id: \.offset) { _, toolCall in
                        toolCallRow(toolCall)
                    }
                }
                .padding(.top, 4)
                .accessibilityElement(children: .contain)
                .accessibilityFocused($accessibilityFocusState, equals: .toolCalls)
            }
        }
        .onChange(of: isToolCallsExpanded) { _, newValue in
            accessibilityFocusState = newValue ? .toolCalls : .disclosure
        }
    }
    
    private func toolCallRow(_ toolCall: ToolCallSummary) -> some View {
        HStack(spacing: 8) {
            statusIcon(for: toolCall.status)
            VStack(alignment: .leading, spacing: 0) {
                Text(toolCall.name)
                    .font(.compound.bodySMSemibold)
                Text(toolCall.summary)
                    .font(.compound.bodyXS)
                    .foregroundColor(.compound.textSecondary)
            }
        }
    }
    
    @ViewBuilder
    private func statusIcon(for status: ToolCallSummary.Status) -> some View {
        switch status {
        case .pending:
            CompoundIcon(\.time, size: .xSmall, relativeTo: .compound.bodyXS)
                .foregroundColor(.compound.iconSecondary)
        case .done:
            CompoundIcon(\.check, size: .xSmall, relativeTo: .compound.bodyXS)
                .foregroundColor(.compound.iconSuccessPrimary)
        case .failed:
            CompoundIcon(\.error, size: .xSmall, relativeTo: .compound.bodyXS)
                .foregroundColor(.compound.iconCriticalPrimary)
        case .other:
            CompoundIcon(\.info, size: .xSmall, relativeTo: .compound.bodyXS)
                .foregroundColor(.compound.iconSecondary)
        }
    }
}

struct AgentTurnRoomTimelineView_Previews: PreviewProvider, TestablePreview {
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
        AgentTurnRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                      timestamp: .mock,
                                                      isOutgoing: false,
                                                      isEditable: false,
                                                      canBeRepliedTo: true,
                                                      sender: .init(id: "@agent:example.com"),
                                                      content: .init(body: "Final reply, no tool calls.")))
        
        AgentTurnRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                      timestamp: .mock,
                                                      isOutgoing: false,
                                                      isEditable: false,
                                                      canBeRepliedTo: true,
                                                      sender: .init(id: "@agent:example.com"),
                                                      content: .init(body: "Done reading and searching.",
                                                                     toolCalls: [
                                                                         ToolCallSummary(name: "read_file", status: .done, summary: "Read Foo.swift"),
                                                                         ToolCallSummary(name: "search", status: .pending, summary: "Searching for usages...")
                                                                     ])))
    }
}
