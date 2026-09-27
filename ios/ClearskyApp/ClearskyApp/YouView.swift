import SwiftUI
import ClearskyCore

/// The "You" screen — settings and account.
///
/// Per `01 Product Scope.dc.html` §6 Screen inventory, "You" — Purpose: "Settings and
/// account". Key states/actions: "Privacy card, morning summary toggle,
/// protect-evenings toggle, inner circle, weekly recap, plan, connected accounts." This
/// file renders exactly that list, in that order, plus a direct route to Digest
/// alongside Weekly recap (per this build task's explicit instruction — `DigestView`'s
/// own doc comment only names Weekly recap as the screen that links out to it, so this
/// is an additional direct route, not a replacement for that one, and neither link is
/// wired anywhere yet since this whole screen is not reachable from the running app —
/// see the next paragraph).
///
/// This screen is not reachable from the running app yet — wiring it in as a 4th tab is
/// a separate task, later this shift. This file only needs to compile, preview, and be
/// unit-testable standalone, the same scoping `PrivacyView`/`DigestView`/
/// `WeeklyRecapView` already used for themselves. It adds no call site into
/// `RootView.swift`, `ClearskyApp.swift`, `PromisesView.swift` or
/// `SharedDraftStoreObserver.swift`.
///
/// ## What's real here vs. an honest placeholder
///
/// - **Privacy**, **Weekly recap**, **Digest** — real `NavigationLink`s to the already-
///   built `PrivacyView`/`WeeklyRecapView`/`DigestView`.
/// - **Morning summary**, **Protect evenings** — real, persisted `@AppStorage` toggles
///   (see each property's own doc comment below for exactly what "real" does and does
///   not mean for each one).
/// - **Connected accounts** — a real, persisted read of `calendarConnected` (see that
///   property's doc comment), rendered as inert, non-interactive text.
/// - **Inner circle**, **Plan** — inert, non-interactive placeholders naming a
///   destination/model that does not exist yet in this codebase, rather than a fake
///   control or an invented number. See each section's doc comment for how that was
///   confirmed.
struct YouView: View {
    @ObservedObject var store: PromiseStore
    let sharedDraftStore: SharedDraftStore

    /// Whether the person wants a morning summary.
    ///
    /// This genuinely persists to `UserDefaults` under `YouViewDefaultsKey
    /// .morningSummaryEnabled` — real, not fake. But **no notification-scheduling code
    /// exists anywhere in this app yet to consume this flag**: `ClearskyCore
    /// /NotificationBudget.swift` only has pure decision-layer types
    /// (`NotificationCategory` and friends) with zero call sites anywhere in
    /// `ClearskyApp` (confirmed via `grep -rn "NotificationBudget" ios/` — it only
    /// appears in two doc comments, `NotificationsPermissionView.swift` and
    /// `NotificationPermissionRequesting.swift`, neither of which schedules anything).
    /// Flipping this toggle does not yet change what the person actually receives. This
    /// is a real, already-scoped gap — there is no scheduler in this codebase to wire it
    /// into yet — not something this task is meant to fix.
    ///
    /// Not `private`: `@testable import ClearskyApp` cannot reach a `private` property
    /// from another file, and `YouViewTests.swift` needs to read/write this exact
    /// property (not a parallel hand-rolled `UserDefaults` call) to prove the real
    /// `@AppStorage` binding round-trips through an injected, disposable suite — same
    /// "scope only as wide as `@testable import` needs" reasoning
    /// `ConnectCalendarViewModel`'s methods already use in this codebase.
    @AppStorage(YouViewDefaultsKey.morningSummaryEnabled) var morningSummaryEnabled = true

    /// Whether the person wants Clearsky to protect their evenings.
    ///
    /// Same honesty note as `morningSummaryEnabled` above: this genuinely persists to
    /// `UserDefaults` under `YouViewDefaultsKey.protectEveningsEnabled`, but nothing in
    /// this codebase yet reads it to change calendar-hold behavior — there is no
    /// "evenings" concept anywhere in `ProtectedTime.swift`/`CalendarHolding.swift`
    /// today. Flipping it persists a preference with no consumer yet.
    ///
    /// Not `private` — see `morningSummaryEnabled`'s doc comment above for why.
    @AppStorage(YouViewDefaultsKey.protectEveningsEnabled) var protectEveningsEnabled = false

    /// Whether the person's calendar is connected, as of the last time they went
    /// through Connect calendar.
    ///
    /// **Read-only in this file** — a different, parallel task this shift is the one
    /// that sets this `true`, via this exact same key string
    /// (`YouViewDefaultsKey.calendarConnected` == `"calendarConnected"`), once calendar
    /// access is actually granted during first run. This screen only ever reads it, to
    /// render the "Connected accounts" row below (`connectedAccountsSection`) — it never
    /// writes to it, and offers no control that would.
    ///
    /// This is a locally-persisted flag, **not a live re-check of EventKit's current
    /// authorization status** — it reflects the outcome the last time the person
    /// completed Connect calendar, and could in principle drift from reality if access
    /// is later revoked in iOS Settings (EventKit's own authorization status would then
    /// disagree with this flag until the person reconnects). This is the same class of
    /// honestly-documented edge case PR #23 ("ios: fix orphaned calendar hold on promise
    /// reschedule") flagged explicitly rather than hiding: that PR's own note on a
    /// denied-access path reads "if calendar access is denied/fails, the *old*
    /// identifier is left attached rather than dropped to nil... keeping the identifier
    /// means a later reschedule attempt can still find and remove it" — a deliberate,
    /// named tradeoff, not an oversight. A real fix here would call
    /// `EKEventStore.authorizationStatus(for: .event)` directly rather than trusting a
    /// persisted flag; that is out of scope for this additive, standalone screen.
    ///
    /// Not `private` — see `morningSummaryEnabled`'s doc comment above for why.
    @AppStorage(YouViewDefaultsKey.calendarConnected) var calendarConnected = false

    /// - Parameter defaults: the `UserDefaults` the three `@AppStorage` properties above
    ///   read and write. Defaults to `.standard` — the real app's shared defaults — so a
    ///   normal call site (`YouView(store:, sharedDraftStore:)`) behaves exactly like
    ///   `PrivacyView`'s own two-parameter init. A test or preview passes a disposable,
    ///   suite-backed instance instead (same isolation trick `PendingDraftsView.swift`'s
    ///   previews use for `SharedDraftStore`), so it never reads or writes the real
    ///   app's shared defaults. See `YouViewTests.swift`.
    init(store: PromiseStore, sharedDraftStore: SharedDraftStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.sharedDraftStore = sharedDraftStore
        _morningSummaryEnabled = AppStorage(
            wrappedValue: true,
            YouViewDefaultsKey.morningSummaryEnabled,
            store: defaults
        )
        _protectEveningsEnabled = AppStorage(
            wrappedValue: false,
            YouViewDefaultsKey.protectEveningsEnabled,
            store: defaults
        )
        _calendarConnected = AppStorage(
            wrappedValue: false,
            YouViewDefaultsKey.calendarConnected,
            store: defaults
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("You")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                Text("Settings and account.")
                    .font(ClearskyFont.ui(15))
                    .foregroundStyle(ClearskyColor.body)

                privacySection
                notificationsSection
                peopleSection
                momentsSection
                planSection
                connectedAccountsSection
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
    }

    // MARK: - Privacy

    /// A real `NavigationLink` to the already-built `PrivacyView`.
    private var privacySection: some View {
        NavigationLink {
            PrivacyView(store: store, sharedDraftStore: sharedDraftStore)
        } label: {
            YouNavigationRow(title: "Privacy", subtitle: "The data promise in full.")
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notifications (morning summary, protect evenings)

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text("NOTIFICATIONS")
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            VStack(spacing: ClearskySpacing.xs) {
                YouToggleRow(
                    title: "Morning summary",
                    subtitle: "Persisted. Nothing sends it yet \u{2014} there is no scheduler in this app.",
                    isOn: $morningSummaryEnabled
                )
                YouToggleRow(
                    title: "Protect evenings",
                    subtitle: "Persisted. Nothing reads it yet to change calendar holds.",
                    isOn: $protectEveningsEnabled
                )
            }
        }
    }

    // MARK: - People (inner circle)

    /// Inert — plain text, not a button or `NavigationLink`. There is no `Person` model
    /// anywhere in this codebase (`grep -ri "struct Person" ios/` returns nothing) and
    /// no Contacts framework integration, so this never invents a count or a working
    /// add-person control. `01 Product Scope.dc.html`'s "Inner circle" first-run screen
    /// describes selecting from detected contacts, but no such screen or model has
    /// landed in `ClearskyApp`/`ClearskyCore` yet.
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text("PEOPLE")
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            YouInertRow(
                title: "Inner circle",
                subtitle: "0 people \u{2014} inner circle isn't built yet."
            )
        }
    }

    // MARK: - Moments (weekly recap, digest)

    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text("MOMENTS")
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            VStack(spacing: ClearskySpacing.xs) {
                NavigationLink {
                    WeeklyRecapView(store: store)
                } label: {
                    YouNavigationRow(title: "Weekly recap", subtitle: "The emotional payoff.")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DigestView(store: store)
                } label: {
                    YouNavigationRow(title: "Digest", subtitle: "The detail behind the recap.")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Plan

    /// Inert — not tappable. No Paywall/Plans screen exists on `main` as of this task
    /// (`grep -rin "PaywallView\|PlansView" ios/` returns nothing), so this shows the
    /// real numbers `PricingPlan` already defines (the one place they live, per that
    /// type's own doc comment, so the marketing site and app can never silently drift
    /// apart) without linking anywhere. Mirrors `ConnectCalendarView.swift`'s "The
    /// privacy note" doc-comment precedent for exactly this situation — a spec element
    /// naming a destination that doesn't exist yet: if a Paywall/Plans screen lands
    /// later, `planSection` below is the one place to swap in a real `NavigationLink` to
    /// it.
    private var planSection: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text("PLAN")
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            YouInertRow(
                title: "\(PricingPlan.yearly.displayPrice) \(PricingPlan.yearly.period)",
                subtitle: "\(PricingPlan.trialDays)-day free trial. Manage plan \u{2014} not available yet."
            )
        }
    }

    // MARK: - Connected accounts

    /// Inert — plain text, not a button. Reads `calendarConnected` only; see that
    /// property's own doc comment for what "connected" does and does not guarantee.
    private var connectedAccountsSection: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text("CONNECTED ACCOUNTS")
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            YouInertRow(
                title: "Calendar",
                subtitle: YouConnectedAccountsDisplay.calendarStatusText(connected: calendarConnected)
            )
        }
    }
}

// MARK: - YouViewDefaultsKey

/// The exact `UserDefaults` key strings this screen's `@AppStorage` properties read and
/// write. Named here, once, rather than as inline string literals scattered across the
/// view and its tests, specifically because `calendarConnected` is also written by a
/// different, parallel task this shift (the first-run Connect calendar flow) — the two
/// features only interoperate if both spell the key identically.
/// `YouViewTests.test_defaultsKeys_matchExactStrings` pins all three literal values.
enum YouViewDefaultsKey {
    static let morningSummaryEnabled = "morningSummaryEnabled"
    static let protectEveningsEnabled = "protectEveningsEnabled"
    static let calendarConnected = "calendarConnected"
}

// MARK: - YouConnectedAccountsDisplay

/// The "Connected accounts" row text, pulled out as a plain, view-independent function
/// — not buried in `YouView`'s body — so a test can prove both wordings without
/// instantiating a view. Same "pull the logic out" reasoning `PrivacyArchiveExporter`/
/// `DigestCalculator` already use in this codebase for their own pure computations.
enum YouConnectedAccountsDisplay {
    static func calendarStatusText(connected: Bool) -> String {
        connected ? "Calendar \u{2014} Connected" : "Calendar \u{2014} Not connected"
    }
}

// MARK: - Row components

/// A tappable row (wrapped in a `NavigationLink` by the caller) with a title, a
/// subtitle, and a trailing chevron — the "goes somewhere real" row style this screen
/// uses for Privacy, Weekly recap and Digest.
private struct YouNavigationRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: ClearskySpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ClearskyFont.ui(15, weight: .semibold))
                    .foregroundStyle(ClearskyColor.inkNavy)
                Text(subtitle)
                    .font(ClearskyFont.ui(12))
                    .foregroundStyle(ClearskyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(ClearskyColor.muted)
        }
        .padding(ClearskySpacing.m)
        .frame(minHeight: ClearskyMetric.minHitTarget)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
    }
}

/// A row with a title, a subtitle, and a real `Toggle` bound to `isOn`.
private struct YouToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ClearskyFont.ui(15, weight: .semibold))
                    .foregroundStyle(ClearskyColor.inkNavy)
                Text(subtitle)
                    .font(ClearskyFont.ui(12))
                    .foregroundStyle(ClearskyColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(ClearskyColor.amberGradientEnd)
        .padding(ClearskySpacing.m)
        .frame(minHeight: ClearskyMetric.minHitTarget)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
    }
}

/// A row with a title and a subtitle and nothing else — no button, no `NavigationLink`,
/// no tap gesture. Used for every honest placeholder on this screen (Inner circle,
/// Plan, Connected accounts) so it is visibly, structurally inert rather than looking
/// tappable and doing nothing.
private struct YouInertRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(ClearskyFont.ui(15, weight: .semibold))
                .foregroundStyle(ClearskyColor.inkNavy)
            Text(subtitle)
                .font(ClearskyFont.ui(12))
                .foregroundStyle(ClearskyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ClearskySpacing.m)
        .frame(minHeight: ClearskyMetric.minHitTarget)
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

// MARK: - Previews

/// Builds a disposable, file-backed `PromiseStore` — same isolation pattern
/// `PromisesView.swift`'s `makePreviewStore()` uses, so previews never read or pollute a
/// real device's Documents directory.
@MainActor
private func makeYouPreviewStore() -> PromiseStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("you-view-preview-\(UUID().uuidString)")
        .appendingPathExtension("json")
    return PromiseStore(fileURL: url)
}

/// Builds a disposable `UserDefaults` suite-backed `SharedDraftStore` — same isolation
/// pattern `PrivacyView.swift`'s `makePrivacyPreviewDraftStore()` uses, so previews
/// never touch the real App Group.
private func makeYouPreviewDraftStore() -> SharedDraftStore {
    let suiteName = "you-preview-drafts-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return SharedDraftStore(defaults: defaults)
}

/// A disposable `UserDefaults` suite for the `@AppStorage` properties themselves — never
/// the real app's shared defaults (`.standard`) in a preview.
private func makeYouPreviewDefaults() -> UserDefaults {
    UserDefaults(suiteName: "you-preview-defaults-\(UUID().uuidString)")!
}

#Preview("You \u{2014} calendar not connected") {
    NavigationStack {
        YouView(
            store: makeYouPreviewStore(),
            sharedDraftStore: makeYouPreviewDraftStore(),
            defaults: makeYouPreviewDefaults()
        )
    }
}

#Preview("You \u{2014} calendar connected") {
    let defaults = makeYouPreviewDefaults()
    defaults.set(true, forKey: YouViewDefaultsKey.calendarConnected)
    return NavigationStack {
        YouView(
            store: makeYouPreviewStore(),
            sharedDraftStore: makeYouPreviewDraftStore(),
            defaults: defaults
        )
    }
}
