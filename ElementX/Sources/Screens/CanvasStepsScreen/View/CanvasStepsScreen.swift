//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct CanvasStepsScreen: View {
    @Bindable var context: CanvasStepsScreenViewModel.Context

    var body: some View {
        Form {
            Section {
                ForEach(context.viewState.steps, id: \.id) { step in
                    ListRow(kind: .custom { stepRow(step) })
                }
            }
        }
        .compoundList()
        .navigationTitle(context.viewState.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.actionDone) {
                    context.send(viewAction: .close)
                }
            }
        }
    }

    private func stepRow(_ step: CanvasStep) -> some View {
        HStack(spacing: 12) {
            statusIcon(for: step.status)
            Text(step.label)
                .font(.compound.bodyMD)
                .foregroundColor(.compound.textPrimary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Adapted from `AgentTurnRoomTimelineView.statusIcon(for:)`, which uses the same icon/colour
    /// tokens for `ToolCallSummary.Status`. `CanvasStep.Status` has an `.inProgress` case instead
    /// of `.failed`, mapped to the "time" icon to indicate the step is currently underway.
    @ViewBuilder
    private func statusIcon(for status: CanvasStep.Status) -> some View {
        switch status {
        case .pending:
            CompoundIcon(\.circle, size: .small, relativeTo: .compound.bodyMD)
                .foregroundColor(.compound.iconTertiary)
        case .inProgress:
            CompoundIcon(\.time, size: .small, relativeTo: .compound.bodyMD)
                .foregroundColor(.compound.iconSecondary)
        case .done:
            CompoundIcon(\.check, size: .small, relativeTo: .compound.bodyMD)
                .foregroundColor(.compound.iconSuccessPrimary)
        case .other:
            CompoundIcon(\.info, size: .small, relativeTo: .compound.bodyMD)
                .foregroundColor(.compound.iconSecondary)
        }
    }
}

// MARK: - Previews

struct CanvasStepsScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    static let allDoneViewModel = makeViewModel(steps: [
        CanvasStep(id: "s1", label: "Read existing code", status: .done),
        CanvasStep(id: "s2", label: "Run tests", status: .done)
    ])

    static var previews: some View {
        ElementNavigationStack {
            CanvasStepsScreen(context: viewModel.context)
        }
        .previewDisplayName("In progress")

        ElementNavigationStack {
            CanvasStepsScreen(context: allDoneViewModel.context)
        }
        .previewDisplayName("All done")
    }

    static func makeViewModel(steps: [CanvasStep] = [
        CanvasStep(id: "s1", label: "Read existing code", status: .done),
        CanvasStep(id: "s2", label: "Wait for approval", status: .inProgress),
        CanvasStep(id: "s3", label: "Run tests", status: .pending)
    ]) -> CanvasStepsScreenViewModel {
        CanvasStepsScreenViewModel(title: "Refactor auth module", steps: steps)
    }
}
