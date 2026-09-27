import SwiftUI
import ClearskyCore

/// The "Paywall" screen.
///
/// Per `01 Product Scope.dc.html` §6 Screen inventory, "Paywall" — Purpose: "Explain
/// the trial honestly". Key states/actions: "Three-step timeline: unlocks today,
/// reminder day twelve, billing day fourteen." Flow E "Trial to paid": "Paywall →
/// plans → start trial → Today." This file builds the screen itself only — wiring it
/// into the app's real navigation (first run, a trial-expiration prompt, or a
/// `You`/Settings entry point) is a later task, the same scoping every other
/// standalone screen this shift has used (`DigestView.swift`, `PrivacyView.swift`,
/// `PlansView.swift`). It adds no call site into `RootView.swift`, `YouView.swift` or
/// any other existing file.
///
/// ## Why "start trial" lives on `PlansView`, not here
///
/// Flow E's three steps read "Paywall → plans → start trial" as three *separate*
/// beats — the trial actually starts once a plan is chosen, on the Plans screen, not
/// before. This screen's own spec entry never mentions choosing a plan or starting
/// anything; its whole job (per the "Key states/actions" column quoted above) is the
/// honest three-step trial timeline. So `PaywallView`'s one action is a plain "See
/// plans" `NavigationLink` into `PlansView` — the same in-flow, same-feature push
/// `DigestView.swift`'s "one thing to watch" card already uses to reach
/// `PromiseDetailView`, not a root-navigation change. `PlansView`'s own primary CTA is
/// where the actual "start trial" language and action live. This view assumes it
/// already lives inside a `NavigationStack` supplied by its eventual container, the
/// same assumption `DigestView` documents for itself.
///
/// ## The copy
///
/// The headline and mission line below quote `01 Product Scope.dc.html`'s own "One
/// product, everything included. No tiers, no feature gates." (§10) and its "IN ONE
/// SENTENCE" mission statement, verbatim, rather than inventing new marketing claims.
/// The three-step trial timeline reuses the exact structure and wording
/// `06 M04 Pricing.dc.html`'s "THE TRIAL, HONESTLY" section already established for
/// the marketing site ("Today — everything unlocks.", "Day _ — we remind you it ends
/// soon.", "Day _ — billing starts, unless you cancel.") — this screen and that page
/// describe the same trial, so reusing its exact phrasing (with the day numbers
/// computed via `TrialTimeline` below, never hardcoded) keeps the two from silently
/// drifting apart, matching §10's own explicit rule that the pricing numbers must
/// never drift between the marketing site and the app.
struct PaywallView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("Everything included")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                Text("Clearsky is a relationship and commitment operating system: it sorts the noise out of your day, turns the messages that matter into plans you actually keep, and protects the time those plans need.")
                    .font(ClearskyFont.editorial(16))
                    .foregroundStyle(ClearskyColor.body)
                    .fixedSize(horizontal: false, vertical: true)

                Text("One product, everything included. No tiers, no feature gates.")
                    .font(ClearskyFont.ui(15, weight: .semibold))
                    .foregroundStyle(ClearskyColor.inkNavy)

                timeline

                Text("Clearsky never sends a message on your behalf \u{2014} the trial unlocks the whole product, nothing held back to upsell later.")
                    .font(ClearskyFont.ui(13))
                    .foregroundStyle(ClearskyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)

                primaryButton
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
    }

    // MARK: - The three-step trial timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text("THE TRIAL, HONESTLY")
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            VStack(spacing: ClearskySpacing.xs) {
                TrialTimelineRow(dayLabel: "Today", detail: "Everything unlocks.")
                TrialTimelineRow(
                    dayLabel: "Day \(TrialTimeline.reminderDay)",
                    detail: "We remind you it ends soon."
                )
                TrialTimelineRow(
                    dayLabel: "Day \(PricingPlan.trialDays)",
                    detail: "Billing starts, unless you cancel."
                )
            }
        }
    }

    // MARK: - Primary action

    /// Pushes into `PlansView` — see the type-level doc for why "start trial" itself
    /// is not this button's label or action.
    private var primaryButton: some View {
        NavigationLink {
            PlansView()
        } label: {
            Text("See plans")
                .font(ClearskyFont.ui(16, weight: .semibold))
                .foregroundStyle(ClearskyColor.amberInk)
                .frame(maxWidth: .infinity)
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
}

/// One row of the three-step trial timeline — a day label plus the honest detail
/// behind it, mirroring `NotificationExpectationRow`
/// (`NotificationsPermissionView.swift`)'s "title + detail card" shape.
private struct TrialTimelineRow: View {
    let dayLabel: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ClearskySpacing.sm) {
            Text(dayLabel.uppercased())
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.04 * 12)
                .foregroundStyle(ClearskyColor.amberLabelInk)
                .frame(width: 64, alignment: .leading)

            Text(detail)
                .font(ClearskyFont.ui(14))
                .foregroundStyle(ClearskyColor.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ClearskySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - TrialTimeline

/// Pure, view-independent trial-timeline math — no SwiftUI dependency, directly
/// testable (`PaywallViewTests`), same "pull the logic out of the view" reasoning
/// `DigestCalculator`/`PlanPricing` use elsewhere in this codebase.
enum TrialTimeline {
    /// How many days before the trial ends the reminder fires. `01 Product Scope.dc.html`
    /// §6 states this as a fixed fact of the *current* trial length ("reminder day
    /// twelve, billing day fourteen" for a fourteen-day trial), not a percentage or
    /// ratio — modeled here as a fixed lead time subtracted from
    /// `PricingPlan.trialDays`, rather than a fraction of it, so a future change to
    /// the trial length is a deliberate decision about this constant too, never a
    /// silent rescale.
    static let reminderLeadDays = 2

    /// The reminder day, computed from `PricingPlan.trialDays` rather than hardcoded —
    /// matches §6's "reminder day twelve" for the trial length in effect today.
    static var reminderDay: Int {
        PricingPlan.trialDays - reminderLeadDays
    }
}

// MARK: - Preview

#Preview("Paywall") {
    NavigationStack {
        PaywallView()
    }
}
