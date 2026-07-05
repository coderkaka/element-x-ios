//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct AgentChoiceRequestRoomTimelineView: View {
    let timelineItem: AgentChoiceRequestRoomTimelineItem
    
    @EnvironmentObject private var context: TimelineViewModel.Context
    @State private var pendingSelection: Set<String> = []
    
    private var content: AgentChoiceRequestRoomTimelineItemContent {
        timelineItem.content
    }
    
    private var eventID: String? {
        timelineItem.id.eventID
    }
    
    /// The state content read from the `io.element.agent.choice_request` room state event keyed by
    /// this message's event ID (state is the only source of truth for this — see
    /// `AgentChoiceRequestRoomTimelineItemContent`). `nil` while unfetched.
    private var stateContent: AgentChoiceRequestStateContent? {
        guard let eventID, let rawStateEvent = context.viewState.fetchedStateEvents[stateEventKey(for: eventID)] else {
            return nil
        }
        return AgentChoiceRequestStateContent(parsingFrom: rawStateEvent)
    }
    
    private func stateEventKey(for eventID: String) -> StateEventKey {
        StateEventKey(eventType: AgentChoiceRequestRoomTimelineItemContent.msgType, stateKey: eventID)
    }
    
    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            VStack(alignment: .leading, spacing: 8) {
                Text(content.question.isEmpty ? content.body : content.question)
                    .font(.compound.bodyMD)
                    .foregroundColor(.compound.textPrimary)
                
                if let resolvedSelection = stateContent?.resolvedSelection, !resolvedSelection.isEmpty {
                    resolvedView(selectedIDs: resolvedSelection)
                } else if stateContent?.isCancelled == true {
                    cancelledView
                } else if content.multiSelect {
                    multiSelectView
                } else {
                    singleSelectView
                }
            }
        }
        .task(id: eventID) {
            guard let eventID else { return }
            context.send(viewAction: .fetchStateEvent(eventType: AgentChoiceRequestRoomTimelineItemContent.msgType, stateKey: eventID))
        }
    }
    
    private var singleSelectView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(content.options, id: \.id) { option in
                Button(option.label) {
                    send(selectedIDs: [option.id])
                }
                .buttonStyle(.compound(.secondary, size: .medium))
            }
        }
    }
    
    private var multiSelectView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(content.options, id: \.id) { option in
                Button {
                    toggle(option.id)
                } label: {
                    HStack {
                        if pendingSelection.contains(option.id) {
                            CompoundIcon(\.checkCircleSolid, size: .small, relativeTo: .compound.bodyMD)
                        } else {
                            CompoundIcon(\.circle, size: .small, relativeTo: .compound.bodyMD)
                        }
                        Text(option.label)
                    }
                }
                .buttonStyle(.compound(.secondary, size: .medium))
            }
            
            Button(UntranslatedL10n.screenRoomTimelineAgentChoiceConfirmButton) {
                send(selectedIDs: pendingSelection)
            }
            .buttonStyle(.compound(.primary, size: .medium))
            .disabled(pendingSelection.isEmpty)
        }
    }
    
    private func resolvedView(selectedIDs: [String]) -> some View {
        let labels = selectedIDs.compactMap { id in content.options.first { $0.id == id }?.label }
        return Text("\(UntranslatedL10n.screenRoomTimelineAgentChoiceSelectedPrefix): \(labels.joined(separator: ", "))")
            .font(.compound.bodySM)
            .foregroundColor(.compound.textSecondary)
    }
    
    private var cancelledView: some View {
        Text(UntranslatedL10n.screenRoomTimelineAgentChoiceCancelled)
            .font(.compound.bodySM)
            .foregroundColor(.compound.textSecondary)
    }
    
    private func toggle(_ optionID: String) {
        if pendingSelection.contains(optionID) {
            pendingSelection.remove(optionID)
        } else {
            pendingSelection.insert(optionID)
        }
    }
    
    private func send(selectedIDs: Set<String>) {
        guard let eventID else { return }
        let labels = content.options.filter { selectedIDs.contains($0.id) }.map(\.label)
        let body = "\(UntranslatedL10n.screenRoomTimelineAgentChoiceSelectedPrefix):\n" + labels.map { "• \($0)" }.joined(separator: "\n")
        context.send(viewAction: .handleChoiceRequestAction(.sendResponse(requestEventID: eventID, body: body)))
    }
}

struct AgentChoiceRequestRoomTimelineView_Previews: PreviewProvider, TestablePreview {
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
        AgentChoiceRequestRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                               timestamp: .mock,
                                                               isOutgoing: false,
                                                               isEditable: false,
                                                               canBeRepliedTo: true,
                                                               sender: .init(id: "@agent:example.com"),
                                                               content: .init(body: "Which environment?",
                                                                              question: "Which environment should this deploy to?",
                                                                              options: [ChoiceOption(id: "test", label: "Test"),
                                                                                        ChoiceOption(id: "staging", label: "Staging"),
                                                                                        ChoiceOption(id: "prod", label: "Production")],
                                                                              multiSelect: false)))
        
        AgentChoiceRequestRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                               timestamp: .mock,
                                                               isOutgoing: false,
                                                               isEditable: false,
                                                               canBeRepliedTo: true,
                                                               sender: .init(id: "@agent:example.com"),
                                                               content: .init(body: "Which reviewers?",
                                                                              question: "Which reviewers should be added?",
                                                                              options: [ChoiceOption(id: "a", label: "Alice"),
                                                                                        ChoiceOption(id: "b", label: "Bob")],
                                                                              multiSelect: true)))
        
        AgentChoiceRequestRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                               timestamp: .mock,
                                                               isOutgoing: false,
                                                               isEditable: false,
                                                               canBeRepliedTo: true,
                                                               sender: .init(id: "@agent:example.com"),
                                                               content: .init(body: "Which environment?",
                                                                              question: "Which environment should this deploy to?",
                                                                              options: [ChoiceOption(id: "test", label: "Test"),
                                                                                        ChoiceOption(id: "staging", label: "Staging"),
                                                                                        ChoiceOption(id: "prod", label: "Production")],
                                                                              multiSelect: false,
                                                                              resolvedSelection: ["staging"])))
    }
}
