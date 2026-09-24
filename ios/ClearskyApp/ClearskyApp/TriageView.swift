import SwiftUI
import ClearskyCore

/// The Triage screen. Root README "Interactions and behaviour": "Triage advances one
/// card at a time. Every action maps to exactly one named outcome: Responded, Planned,
/// Snoozed, Waiting on them, Let go. The completion screen tallies in those words."
///
/// This view shows exactly one `TriageCardView` at a time; tapping any action (primary
/// or a quieter alternative) records the real `resultingState` from that action's
/// `TriageResolvedAction` and advances to the next item. When the queue is empty, the
/// completion screen tallies outcomes using `Outcome.displayName` — the same named
/// vocabulary the state machine itself uses, not a screen-local copy of it.
struct TriageView: View {
    let items: [TriageItem]

    @State private var index = 0
    @State private var tally: [Outcome: Int] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header

            if items.isEmpty {
                emptyQueueState
            } else if index < items.count {
                ScrollView {
                    TriageCardView(item: items[index]) { resolved in
                        record(resolved)
                    }
                    .padding(.horizontal, ClearskySpacing.l)
                    .padding(.top, ClearskySpacing.m)
                }
            } else {
                completionState
            }
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xxs) {
            Text("Triage")
                .font(ClearskyFont.display(24))
                .foregroundStyle(ClearskyColor.inkNavy)
                .displayHeadlineStyle()

            if !items.isEmpty {
                Text(index < items.count ? "\(index + 1) of \(items.count)" : "Done \u{2014} \(items.count) of \(items.count)")
                    .font(ClearskyFont.ui(13))
                    .foregroundStyle(ClearskyColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ClearskySpacing.l)
        .padding(.top, ClearskySpacing.m)
        .padding(.bottom, ClearskySpacing.s)
    }

    private func record(_ resolved: TriageResolvedAction) {
        tally[resolved.resultingState, default: 0] += 1
        withAnimation(.easeInOut(duration: 0.2)) {
            index += 1
        }
    }

    private var emptyQueueState: some View {
        VStack(spacing: ClearskySpacing.s) {
            Text("Nothing to triage")
                .font(ClearskyFont.ui(16, weight: .semibold))
                .foregroundStyle(ClearskyColor.inkNavy)
            Text("New items will queue up here.")
                .font(ClearskyFont.ui(14))
                .foregroundStyle(ClearskyColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var completionState: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.l) {
            Spacer()

            VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
                Text("All triaged")
                    .font(ClearskyFont.display(22))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                Text("Here's what happened to each one.")
                    .font(ClearskyFont.ui(14))
                    .foregroundStyle(ClearskyColor.muted)
            }

            VStack(spacing: ClearskySpacing.xs) {
                ForEach(Outcome.allCases.filter { tally[$0] != nil }, id: \.self) { outcome in
                    HStack {
                        Text(outcome.displayName)
                            .font(ClearskyFont.ui(15, weight: .medium))
                            .foregroundStyle(ClearskyColor.body)
                        Spacer()
                        Text("\(tally[outcome] ?? 0)")
                            .font(ClearskyFont.ui(15, weight: .semibold))
                            .foregroundStyle(outcome.statusColor)
                    }
                    .padding(.horizontal, ClearskySpacing.m)
                    .frame(minHeight: ClearskyMetric.minHitTarget)
                    .background(
                        RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                            .fill(ClearskyColor.surfacePrimary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                            .stroke(ClearskyColor.hairline, lineWidth: 1)
                    )
                }
            }

            Button {
                withAnimation { restart() }
            } label: {
                Text("Start over")
                    .font(ClearskyFont.ui(15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: ClearskyMetric.minHitTarget)
                    .foregroundStyle(ClearskyColor.amberInk)
                    .background(
                        LinearGradient(
                            colors: [ClearskyColor.amberGradientStart, ClearskyColor.amberGradientEnd],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, ClearskySpacing.l)
    }

    private func restart() {
        index = 0
        tally = [:]
    }
}

#Preview {
    TriageView(items: SampleData.triageItems)
}
