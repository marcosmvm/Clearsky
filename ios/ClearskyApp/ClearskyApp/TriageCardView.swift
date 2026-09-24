import SwiftUI
import ClearskyCore

/// The card both Today and Triage build on: one item, rendered as the README requires
/// — "a WHY NOW rationale drawn from real signals, an IF YOU DO NOTHING / IF NOT
/// consequence, one recommended action selected from the item's own context, and
/// quieter alternatives" — never a flat menu of equal-weight cards.
///
/// Every string this view shows for the WHY NOW / IF NOT / action fields comes from
/// `item.presentation` (a `ClearskyCore.TriagePresentation`), not from a literal typed
/// into this view. The recommended action renders as a full-width primary pill;
/// alternatives render smaller and secondary, directly under it — that size and order
/// difference *is* the "recommended reads as primary, alternatives as quieter" rule.
struct TriageCardView: View {
    let item: TriageItem
    var onAction: (TriageResolvedAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.l) {
            header

            Text(item.messagePreview)
                .font(ClearskyFont.editorial(17))
                .foregroundStyle(ClearskyColor.body)
                .fixedSize(horizontal: false, vertical: true)

            explanationSection(
                label: "WHY NOW",
                text: item.presentation.explanation.whyNow,
                labelColor: ClearskyColor.secondaryInk
            )

            if !item.presentation.explanation.signals.isEmpty {
                signalChips
            }

            explanationSection(
                label: "IF YOU DO NOTHING",
                text: item.presentation.explanation.ifNoAction,
                labelColor: ClearskyColor.amberLabelInk
            )

            actions
        }
        .padding(ClearskySpacing.l)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: ClearskySpacing.m) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [ClearskyColor.skyStart, ClearskyColor.skyEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Text(item.initials)
                    .font(ClearskyFont.ui(15, weight: .semibold))
                    .foregroundStyle(ClearskyColor.inkNavy)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.personName)
                    .font(ClearskyFont.ui(16, weight: .semibold))
                    .foregroundStyle(ClearskyColor.inkNavy)
                if item.isInnerCircle {
                    Text("Inner circle")
                        .font(ClearskyFont.ui(12, weight: .medium))
                        .foregroundStyle(ClearskyColor.muted)
                }
            }

            Spacer()

            Text(item.presentation.state.displayName)
                .font(ClearskyFont.ui(12, weight: .semibold))
                .foregroundStyle(item.presentation.state.statusColor)
                .padding(.horizontal, ClearskySpacing.s)
                .padding(.vertical, ClearskySpacing.xxs)
                .background(
                    Capsule().fill(item.presentation.state.statusColor.opacity(0.12))
                )
        }
    }

    private func explanationSection(label: String, text: String, labelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xxs) {
            Text(label)
                .font(ClearskyFont.ui(11, weight: .semibold))
                .tracking(0.08 * 11)
                .foregroundStyle(labelColor)
            Text(text)
                .font(ClearskyFont.ui(14))
                .foregroundStyle(ClearskyColor.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signalChips: some View {
        FlowChips(signals: item.presentation.explanation.signals)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            if let recommended = item.presentation.recommended {
                Button {
                    onAction(recommended)
                } label: {
                    HStack {
                        Image(systemName: recommended.source.symbolName)
                        Text(recommended.source.actionLabel)
                            .font(ClearskyFont.ui(15, weight: .semibold))
                        Spacer()
                        Text("\u{2192} \(recommended.resultingState.displayName)")
                            .font(ClearskyFont.ui(12, weight: .medium))
                            .opacity(0.8)
                    }
                    .foregroundStyle(ClearskyColor.amberInk)
                    .padding(.horizontal, ClearskySpacing.m)
                    .frame(minHeight: ClearskyMetric.minHitTarget)
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
            }

            if !item.presentation.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
                    Text("QUIETER OPTIONS")
                        .font(ClearskyFont.ui(10, weight: .semibold))
                        .tracking(0.08 * 10)
                        .foregroundStyle(ClearskyColor.muted)

                    ForEach(item.presentation.alternatives, id: \.self) { alternative in
                        Button {
                            onAction(alternative)
                        } label: {
                            HStack {
                                Image(systemName: alternative.source.symbolName)
                                    .font(.system(size: 13))
                                Text(alternative.source.actionLabel)
                                    .font(ClearskyFont.ui(13, weight: .medium))
                                Spacer()
                                Text("\u{2192} \(alternative.resultingState.displayName)")
                                    .font(ClearskyFont.ui(11))
                            }
                            .foregroundStyle(ClearskyColor.secondaryInk)
                            .padding(.horizontal, ClearskySpacing.m)
                            .frame(minHeight: ClearskyMetric.minHitTarget)
                            .background(
                                RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                                    .fill(ClearskyColor.surfaceSecondary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                                    .stroke(ClearskyColor.hairlineStrong, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// A small wrapping chip row for the real `TriageExplanation.Signal` values behind
/// `whyNow` — makes the "drawn from real signals" part of the README requirement
/// visible as data, not just prose.
private struct FlowChips: View {
    let signals: [TriageExplanation.Signal]

    var body: some View {
        HStack(spacing: ClearskySpacing.xs) {
            ForEach(signals, id: \.self) { signal in
                Text(signal.chipLabel)
                    .font(ClearskyFont.ui(11, weight: .medium))
                    .foregroundStyle(ClearskyColor.secondaryInk)
                    .padding(.horizontal, ClearskySpacing.s)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(ClearskyColor.surfaceSecondary)
                    )
            }
            Spacer(minLength: 0)
        }
    }
}
