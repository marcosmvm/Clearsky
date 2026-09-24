import Foundation

/// The three ways V1 can be paid for, and nothing else.
///
/// `01 Product Scope.dc.html` §10 "Pricing" states the product's own rule for these
/// numbers: "The same three numbers appear on the marketing pricing page and in the
/// app paywall. Any change must be made in both places at once." A future
/// Paywall/Plans screen that reads its price, period and trial length from this
/// type — instead of a screen hardcoding `"$49.99"` or `"14"` inline — is what makes
/// that rule enforceable in code rather than just in the doc: there is exactly one
/// place these numbers live, so the marketing site and the app paywall can never
/// silently drift apart from each other.
///
/// V1 has three plans, no weekly plan: `.yearly` (the default), `.monthly` and
/// `.lifetime`. Every subscription plan — `.yearly` and `.monthly` alike — offers
/// the same 14-day free trial before billing starts; `.lifetime` is a one-time
/// purchase, so there is nothing to trial.
public enum PricingPlan: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case yearly
    case monthly
    case lifetime

    /// The exact price for this plan, matching `01 Product Scope.dc.html` §10 and
    /// `06 M04 Pricing.dc.html`: $49.99 a year, $6.99 a month, $129 once.
    public var priceUSD: Decimal {
        switch self {
        case .yearly:
            return Decimal(string: "49.99")!
        case .monthly:
            return Decimal(string: "6.99")!
        case .lifetime:
            return Decimal(string: "129")!
        }
    }

    /// The price formatted for display, e.g. `"$49.99"`. Always two decimal places
    /// except `.lifetime`, which the marketing and app copy both write as `"$129"`
    /// with no trailing `.00`.
    public var displayPrice: String {
        switch self {
        case .yearly:
            return "$49.99"
        case .monthly:
            return "$6.99"
        case .lifetime:
            return "$129"
        }
    }

    /// The billing period, in the same words the marketing site and app paywall
    /// use next to the price: "a year", "a month", or "once, forever" for the
    /// one-time lifetime purchase.
    public var period: String {
        switch self {
        case .yearly:
            return "a year"
        case .monthly:
            return "a month"
        case .lifetime:
            return "once, forever"
        }
    }

    /// Whether this is the plan pre-selected on the Plans screen. Only `.yearly` is
    /// the default, matching `01 Product Scope.dc.html` §10 ("a year · save 40% ·
    /// default") and the Plans-screen description in §6 ("Yearly (selected, Save
    /// 40%), monthly, lifetime.").
    public var isDefault: Bool {
        self == .yearly
    }

    /// The free trial length in days, in effect for both subscription plans
    /// (`.yearly` and `.monthly`) — `.lifetime` is a one-time purchase and has no
    /// trial to speak of. `01 Product Scope.dc.html` §10 and §6 both call this
    /// "14 days free" / "unlocks today, reminder day twelve, billing day fourteen"
    /// — a single constant here is what keeps the marketing copy, the app paywall
    /// timeline and any future StoreKit introductory-offer configuration agreeing
    /// on the same number.
    public static let trialDays: Int = 14
}
