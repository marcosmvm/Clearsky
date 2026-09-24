import SwiftUI
import ClearskyCore

/// The Today screen. Per root README "Screens": Today and Triage "render, per item: a
/// WHY NOW rationale ... an IF YOU DO NOTHING / IF NOT consequence, one recommended
/// action ... and quieter alternatives. Do not reduce either screen to a menu of
/// equal-weight cards."
///
/// This shell reads that literally: one full `TriageCardView` for the single most
/// pressing item ("Next up"), then the remaining items collapsed into small, quiet
/// rows underneath ("Later today") — never a scrolling stack of identical cards.
struct TodayView: View {
    let items: [TriageItem]
    @State private var lastActionSummary: String?

    private var primary: TriageItem? { items.first }
    private var rest: [TriageItem] { items.isEmpty ? [] : Array(items.dropFirst()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("Today")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                if let summary = lastActionSummary {
                    Text(summary)
                        .font(ClearskyFont.ui(13, weight: .medium))
                        .foregroundStyle(ClearskyColor.keptGreen)
                        .padding(.horizontal, ClearskySpacing.m)
                        .padding(.vertical, ClearskySpacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                                .fill(ClearskyColor.keptGreen.opacity(0.10))
                        )
                }

                if let primary {
                    VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
                        Text("NEXT UP")
                            .font(ClearskyFont.ui(12, weight: .semibold))
                            .tracking(0.08 * 12)
                            .foregroundStyle(ClearskyColor.muted)

                        TriageCardView(item: primary) { resolved in
                            lastActionSummary = "\(primary.personName) \u{2192} \(resolved.resultingState.displayName)"
                        }
                    }
                } else {
                    emptyState
                }

                if !rest.isEmpty {
                    VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
                        Text("LATER TODAY")
                            .font(ClearskyFont.ui(12, weight: .semibold))
                            .tracking(0.08 * 12)
                            .foregroundStyle(ClearskyColor.muted)

                        VStack(spacing: ClearskySpacing.xs) {
                            ForEach(rest) { item in
                                LaterTodayRow(item: item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
            Text("All clear")
                .font(ClearskyFont.ui(16, weight: .semibold))
                .foregroundStyle(ClearskyColor.inkNavy)
            Text("Nothing needs you right now.")
                .font(ClearskyFont.ui(14))
                .foregroundStyle(ClearskyColor.muted)
        }
        .padding(ClearskySpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
    }
}

/// A quiet, compact row — deliberately smaller and lower-contrast than the primary
/// `TriageCardView` so "Later today" never competes visually with "Next up". Still
/// shows the item's real recommended action label (from `TriagePresentation`), just
/// without the full WHY NOW / IF NOT body copy or alternative buttons.
private struct LaterTodayRow: View {
    let item: TriageItem

    var body: some View {
        HStack(spacing: ClearskySpacing.m) {
            Circle()
                .fill(ClearskyColor.surfaceSecondary)
                .frame(width: 32, height: 32)
                .overlay(
                    Text(item.initials)
                        .font(ClearskyFont.ui(11, weight: .semibold))
                        .foregroundStyle(ClearskyColor.secondaryInk)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.personName)
                    .font(ClearskyFont.ui(14, weight: .medium))
                    .foregroundStyle(ClearskyColor.body)
                if let recommended = item.presentation.recommended {
                    Text(recommended.source.actionLabel)
                        .font(ClearskyFont.ui(12))
                        .foregroundStyle(ClearskyColor.muted)
                }
            }

            Spacer()

            Text(item.presentation.state.displayName)
                .font(ClearskyFont.ui(11, weight: .medium))
                .foregroundStyle(item.presentation.state.statusColor)
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

#Preview {
    TodayView(items: SampleData.triageItems)
}
