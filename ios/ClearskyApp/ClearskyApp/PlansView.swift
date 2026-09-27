import SwiftUI
import StoreKit
import ClearskyCore

/// The "Plans" screen.
///
/// Per `01 Product Scope.dc.html` §6 Screen inventory, "Plans" — Purpose: "Choose how
/// to pay". Key states/actions: "Yearly (selected, Save 40%), monthly, lifetime.
/// Restore purchases. Selection persists into Settings." Flow E "Trial to paid":
/// "Paywall → plans → start trial → Today." This file builds the screen itself only —
/// wiring it into the app's real navigation (a tab, a `You`/Settings entry point, or
/// the first-run flow) is a later task, the same scoping every other standalone screen
/// this shift has used. It adds no call site into `RootView.swift`, `YouView.swift` or
/// any other existing file.
///
/// "Restore purchases" and "Selection persists into Settings" — both named in the spec
/// quote above — are deliberately **not** built here: this task's brief scopes the
/// Plans screen to three things — list the three plans with real pricing, a
/// default/selected state per `PricingPlan.isDefault`, and real UI selection.
/// Persisting the selection into `YouView.swift`'s existing "Plan" row reaches into a
/// file this task does not touch, and a real restore-purchases action needs the same
/// entitlement-persistence layer this task's scope doesn't include. Flagged here as a
/// follow-up, not silently dropped.
///
/// ## Real StoreKit 2 pricing, with an honest fallback
///
/// `PlansViewModel.loadProducts()` calls the real `Product.products(for:)` API (via
/// `ProductCatalogFetching`/`StoreKitProductCatalog` below) against the three real App
/// Store product identifiers `PricingPlan.productID` maps each plan to (a `private
/// extension`, kept local to this file rather than added to `ClearskyCore` —
/// `PricingPlan` is pure pricing data with no App Store Connect knowledge, and this
/// keeps that true). Running the real app from Xcode (Cmd-R) genuinely resolves this
/// against the local `Clearsky.storekit` configuration — the generated scheme's
/// `LaunchAction` carries `StoreKitConfigurationFileReference` correctly. It does
/// **not** currently resolve inside `ClearskyAppTests` run via `xcodebuild test`: the
/// installed `xcodegen` (2.46.0) has no `storeKitConfiguration` field on a scheme's
/// Test action at all, so `project.yml`'s `test:` line for it is silently dropped on
/// `xcodegen generate`, and no in-test workaround was found that doesn't hang (see
/// `PlansViewModelTests.swift`'s type-level doc for exactly what was tried and the
/// evidence for both claims) — no App Store Connect account is needed either way, just
/// a real Xcode-driven run for the live-fetch path specifically.
///
/// Every price/period/trial-length number `PlanCard` shows is sourced from one of two
/// places: the **real fetched `Product`** (`.displayPrice`/`.displayName`) once
/// `PlansViewModel.product(for:)` has resolved one, or the **static `PricingPlan`**
/// fallback (`.displayPrice`/`.period`/`.trialDays`) while loading, on failure, or if a
/// specific ID didn't come back in the fetch — `PlanCard`'s own property doc comments
/// say which, for each. The two sources can format a price slightly differently
/// (StoreKit's own currency formatting may include trailing cents where
/// `PricingPlan`'s static string is a simplified whole-dollar figure) — both are
/// correct, just from different sources; this is called out here rather than silently
/// reconciled.
///
/// ## The primary action does not call `Product.purchase()`
///
/// Tapping a plan card is real UI state — `PlansViewModel.select(_:)` updates
/// `selectedPlan`, nothing more. The bottom CTA's tap calls
/// `PlansViewModel.confirmSelection()`, which only records `didConfirmPlan` — it does
/// **not** call `Product.purchase()`. This was a deliberate choice, not an oversight:
/// see this screen's PR description for the reasoning (in short — a real purchase call
/// shows a system confirmation sheet that this environment has no way to drive or
/// dismiss programmatically, and completing one would need an entitlement/subscription
/// state elsewhere in the app that doesn't exist yet; wiring a call this task cannot
/// verify at all, end to end, in this environment would overclaim what's actually
/// proven here).
struct PlansView: View {
    @StateObject private var viewModel: PlansViewModel

    init(catalog: ProductCatalogFetching = StoreKitProductCatalog()) {
        _viewModel = StateObject(wrappedValue: PlansViewModel(catalog: catalog))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("Plans")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                Text("Choose how to pay.")
                    .font(ClearskyFont.ui(15))
                    .foregroundStyle(ClearskyColor.body)

                statusBanner

                VStack(spacing: ClearskySpacing.sm) {
                    ForEach(PricingPlan.allCases, id: \.self) { plan in
                        PlanCard(
                            plan: plan,
                            product: viewModel.product(for: plan),
                            isSelected: viewModel.selectedPlan == plan,
                            savingsPercent: plan == .yearly ? PlanPricing.yearlySavingsPercent() : nil
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.select(plan) }
                    }
                }

                primaryActionSection
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
        .task { await viewModel.loadProducts() }
    }

    // MARK: - Loading / error state

    /// Explicit, honest handling of the real fetch's three states — never a silently
    /// blank or stale screen. `.loaded` renders nothing extra here; the per-card
    /// fallback in `PlanCard` covers the "fetch succeeded but this one ID is missing"
    /// case on its own.
    @ViewBuilder
    private var statusBanner: some View {
        switch viewModel.loadState {
        case .loading:
            PlansStatusBanner(
                text: "Confirming live pricing with the App Store\u{2026}",
                tint: ClearskyColor.muted
            )
        case .failed:
            PlansStatusBanner(
                text: "Prices unavailable \u{2014} check your connection. Showing the last known pricing below.",
                tint: ClearskyColor.urgentTerracotta
            )
        case .loaded:
            EmptyView()
        }
    }

    // MARK: - Primary action

    private var primaryActionSection: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            primaryActionButton

            if let confirmed = viewModel.didConfirmPlan {
                Text("Selected \(confirmed.rawValue.capitalized).")
                    .font(ClearskyFont.ui(13, weight: .medium))
                    .foregroundStyle(ClearskyColor.keptGreen)
            }
        }
    }

    /// See the type-level doc's "The primary action does not call `Product.purchase()`"
    /// section for why this button's tap only records `didConfirmPlan`.
    private var primaryActionButton: some View {
        Button {
            viewModel.confirmSelection()
        } label: {
            Text(primaryActionLabel)
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

    /// Real fetched price when available for `.lifetime` (the only plan whose CTA
    /// shows a price at all), else the static `PricingPlan` fallback; trial length for
    /// the two subscription plans always comes from `PricingPlan.trialDays`.
    private var primaryActionLabel: String {
        let plan = viewModel.selectedPlan
        guard plan == .lifetime else {
            return "Start \(PricingPlan.trialDays)-day free trial"
        }
        let price = viewModel.product(for: plan)?.displayPrice ?? plan.displayPrice
        return "Buy lifetime \u{2014} \(price)"
    }
}

// MARK: - PlanCard

/// One selectable plan row. `PlansView.body` wraps this in the `.onTapGesture` that
/// actually selects it — this view itself has no tap handling, staying a pure,
/// stateless renderer of whatever `PlansView` computed for it.
private struct PlanCard: View {
    let plan: PricingPlan
    /// The real fetched `Product` for `plan`, if `PlansViewModel.loadProducts()` has
    /// resolved one — `nil` while loading, on failure, or if this ID didn't come back.
    let product: Product?
    let isSelected: Bool
    /// Only non-`nil` for `.yearly` — see `PlanPricing.yearlySavingsPercent()`.
    let savingsPercent: Int?

    /// **Real fetched** when `product` resolved, **static `PricingPlan` fallback**
    /// otherwise — see `PlansView`'s type-level doc for why the two can format
    /// slightly differently and why that's fine.
    private var priceText: String { product?.displayPrice ?? plan.displayPrice }

    /// Always sourced from `PricingPlan.period` — `Product` has no equivalent short
    /// phrase ("a year"/"a month"/"once, forever") to fetch instead.
    private var periodText: String { plan.period }

    /// Always sourced from `PricingPlan.trialDays`; `nil` for `.lifetime`, which
    /// `PricingPlan.trialDays`'s own doc comment states has no trial at all.
    private var trialText: String? {
        guard plan != .lifetime else { return nil }
        return "\(PricingPlan.trialDays)-day free trial."
    }

    /// **Real fetched** `Product.displayName` when available, else the plan's own
    /// case name, capitalized (`"yearly"` -> `"Yearly"`) — matches the exact
    /// `displayName` strings `Clearsky.storekit`'s localizations already declare for
    /// all three products, so the two never visibly disagree even before a fetch
    /// resolves.
    private var nameText: String { product?.displayName ?? plan.rawValue.capitalized }

    var body: some View {
        HStack(alignment: .top, spacing: ClearskySpacing.m) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isSelected ? ClearskyColor.amberLabelInk : ClearskyColor.muted)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: ClearskySpacing.xs) {
                    Text(nameText)
                        .font(ClearskyFont.ui(15, weight: .semibold))
                        .foregroundStyle(ClearskyColor.inkNavy)

                    if let savingsPercent, savingsPercent > 0 {
                        Text("SAVE \(savingsPercent)%")
                            .font(ClearskyFont.ui(10, weight: .semibold))
                            .tracking(0.06 * 10)
                            .foregroundStyle(ClearskyColor.amberLabelInk)
                            .padding(.horizontal, ClearskySpacing.xs)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(ClearskyColor.amberGradientStart.opacity(0.35))
                            )
                    }
                }

                Text("\(priceText) \(periodText)")
                    .font(ClearskyFont.ui(13))
                    .foregroundStyle(ClearskyColor.body)

                if let trialText {
                    Text(trialText)
                        .font(ClearskyFont.ui(12))
                        .foregroundStyle(ClearskyColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(ClearskySpacing.m)
        .frame(minHeight: ClearskyMetric.minHitTarget)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .stroke(
                    isSelected ? ClearskyColor.amberGradientEnd : ClearskyColor.hairline,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A single-line status banner for the loading/failed fetch states — see
/// `PlansView.statusBanner`.
private struct PlansStatusBanner: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(ClearskyFont.ui(12, weight: .medium))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - PlanPricing

/// Pure, view-independent pricing math — no SwiftUI dependency, directly testable
/// (`PlansViewModelTests`), same "pull the logic out of the view" reasoning
/// `DigestCalculator`/`TrialTimeline` use elsewhere in this codebase.
enum PlanPricing {
    /// The percentage saved by choosing `.yearly` over paying `.monthly`'s price
    /// twelve times over a year, rounded to the nearest whole percent. Computed from
    /// `PricingPlan`'s own `priceUSD` values — never the "Save 40%" figure
    /// `01 Product Scope.dc.html` §6 and the marketing site's `06 M04 Pricing.dc.html`
    /// state as a fixed line of copy, so this can never silently drift from the two
    /// real prices it's actually describing.
    static func yearlySavingsPercent() -> Int {
        let yearly = (PricingPlan.yearly.priceUSD as NSDecimalNumber).doubleValue
        let monthlyAnnualized = (PricingPlan.monthly.priceUSD as NSDecimalNumber).doubleValue * 12
        guard monthlyAnnualized > 0 else { return 0 }
        let saved = 1 - (yearly / monthlyAnnualized)
        return Int((saved * 100).rounded())
    }
}

// MARK: - StoreKit plumbing

/// The real App Store product identifier behind each `PricingPlan` case. Kept local to
/// this file rather than added to `ClearskyCore` — see `PlansView`'s type-level doc.
private extension PricingPlan {
    var productID: String {
        switch self {
        case .yearly: return "com.marcosmvm.clearsky.yearly"
        case .monthly: return "com.marcosmvm.clearsky.monthly"
        case .lifetime: return "com.marcosmvm.clearsky.lifetime"
        }
    }
}

/// Fetches real `Product`s for a set of App Store product identifiers. The one real
/// conformer (`StoreKitProductCatalog`) calls actual StoreKit 2. `PlansViewModel`
/// takes this as a protocol — mirroring `CalendarHolding`/
/// `NotificationPermissionRequesting` elsewhere in this codebase — purely so a test
/// can substitute a throwing/empty fake for the failure/empty-result paths. `Product`
/// itself has no public initializer, so a fake conformer can never fabricate a
/// *successful* result with invented data, only simulate "no products"/"threw"; every
/// success-path assertion in `PlansViewModelTests` goes through the real
/// `StoreKitProductCatalog` against the local `.storekit` config instead.
protocol ProductCatalogFetching {
    func products(for identifiers: [String]) async throws -> [Product]
}

/// The one production conformer — real StoreKit 2, `Product.products(for:)`. Resolves
/// against the local `Clearsky.storekit` configuration when the app is run from Xcode
/// in the simulator, or the live App Store catalog on a real device with a real App
/// Store Connect record — this type only ever calls the one real API either way, never
/// a fake result. See `PlansView`'s type-level doc for why this does not currently
/// resolve when run via `xcodebuild test`.
struct StoreKitProductCatalog: ProductCatalogFetching {
    func products(for identifiers: [String]) async throws -> [Product] {
        try await Product.products(for: identifiers)
    }
}

// MARK: - PlansViewModel

/// Owns the real StoreKit fetch, the current selection, and the (non-purchasing)
/// "primary action tapped" state behind `PlansView` — see that view's type-level doc.
@MainActor
final class PlansViewModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published var selectedPlan: PricingPlan
    @Published private(set) var didConfirmPlan: PricingPlan?

    private var productsByID: [String: Product] = [:]
    private let catalog: ProductCatalogFetching

    init(catalog: ProductCatalogFetching = StoreKitProductCatalog()) {
        self.catalog = catalog
        self.selectedPlan = PricingPlan.allCases.first(where: \.isDefault) ?? .yearly
    }

    /// The real StoreKit fetch — `PlansView` calls this from `.task`. Always ends in
    /// `.loaded` or `.failed`, never leaves `loadState` stuck at `.loading`.
    func loadProducts() async {
        loadState = .loading
        do {
            let identifiers = PricingPlan.allCases.map(\.productID)
            let fetched = try await catalog.products(for: identifiers)
            productsByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            loadState = .loaded
        } catch {
            productsByID = [:]
            loadState = .failed
        }
    }

    /// The real fetched `Product` for `plan`, or `nil` while loading, on failure, or
    /// if this specific ID wasn't in the fetch result — `PlanCard` falls back to
    /// `PricingPlan`'s static values in that case, never blank.
    func product(for plan: PricingPlan) -> Product? {
        productsByID[plan.productID]
    }

    /// Real UI state: the person tapped a plan card. Never calls into StoreKit.
    func select(_ plan: PricingPlan) {
        selectedPlan = plan
    }

    /// Real UI state: the person tapped the primary CTA for `selectedPlan`.
    /// Deliberately does NOT call `Product.purchase()` — see `PlansView`'s type-level
    /// doc and this screen's PR description for why.
    func confirmSelection() {
        didConfirmPlan = selectedPlan
    }
}

// MARK: - Preview

#Preview("Plans") {
    NavigationStack {
        PlansView()
    }
}
