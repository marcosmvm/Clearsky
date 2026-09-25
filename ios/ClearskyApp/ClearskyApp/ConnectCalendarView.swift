import SwiftUI
import ClearskyCore

/// The "Connect calendar" first-run screen.
///
/// Per `01 Product Scope.dc.html` §6 Screen inventory, "Connect calendar" — Purpose:
/// "Grant calendar access (EventKit) only". Key states/actions: "One toggle, calendar
/// only; skippable; privacy note links to the full policy. Texts and email are never
/// read here — they arrive by sharing into the app via the Share Sheet. Gmail as a
/// connected account is a later feature, not V1." §7 flow A places this screen second
/// in first run: "Sign in → connect calendar → pick inner circle → notification
/// permission → Today. Every step is skippable except sign-in." This file builds the
/// screen itself only — wiring it into that real first-run navigation order is a
/// later, separate task, the same scoping `NotificationsPermissionView.swift` (the
/// screen this one mirrors) used for its own equivalent note, specifically so it
/// doesn't collide with other in-flight edits to `RootView.swift`.
///
/// This screen deliberately asks for exactly one thing: calendar access via EventKit.
/// `ConnectedAccountKind` (`ClearskyCore/ConnectedAccounts.swift`) also has `.mail` and
/// `.messaging` cases, but per the spec's own text above, texts and email arrive by
/// sharing into the app via the Share Sheet, never by a connected-account toggle here
/// — this screen renders no UI for either of those kinds, and never will; that is not
/// a gap, it is the spec.
///
/// ## Why granting access applies a `ConnectedAccountsTransition`, not a new boolean
///
/// `ConnectedAccounts.swift` already models "which account kinds are connected" as
/// `ConnectedAccountsState.connectedAccountKinds`, with `ConnectedAccountsTransition
/// .apply(_:to:)` as the one pure, total function that changes it. Granting calendar
/// access here calls `CalendarHolding.requestAccess()` (the real EventKit ask) and,
/// only on a `true` result, applies `.connectAccount(.calendar)` to whatever
/// `ConnectedAccountsState` the caller handed in — reusing that exact domain model
/// rather than inventing a parallel `isCalendarConnected: Bool` that could drift out
/// of sync with it. A `false` result (denied) applies no transition at all, so
/// `.calendar` never appears in `connectedAccountKinds` for a denied request.
///
/// This screen does not own where `ConnectedAccountsState` is persisted long-term —
/// there is no persistence layer for it anywhere in this codebase yet. It keeps its
/// own copy in memory only (`ConnectCalendarViewModel.accountsState`, seeded from
/// whatever the caller passed in) and hands the *result* out via `onFinished`, the
/// same "no hidden state, caller decides what happens next" shape
/// `NotificationsPermissionView`'s `onFinished: (Bool) -> Void` already uses.
///
/// ## Why the permission ask is a view model, not inline `@State` on the view
///
/// `grantAccess()`/`skip()` are pulled into `ConnectCalendarViewModel`, a plain
/// `ObservableObject`, rather than living as `@State` + methods directly on
/// `ConnectCalendarView`, so a test can drive them against an injected
/// `CalendarHolding` mock directly (`MockCalendarService`, already built for
/// `EventKitCalendarServiceTests`/`PromisesViewTests` — reused here, not duplicated) —
/// the same reasoning `NotificationsPermissionViewModel` already documents for the
/// directly-analogous Notifications screen.
///
/// ## The privacy note
///
/// The spec's key-states column says the privacy note "links to the full policy."
/// There is no `PrivacyView.swift` (or any other navigable Privacy destination) on
/// `main` as of this screen's build (24 Sep 2026) — a `git grep -i privacyview` under
/// `ios/` at branch-off time turns up nothing, and no `PrivacyView`-adding PR is open
/// or merged yet either. `PromiseDetailView.swift`'s `threadRow` sets the precedent
/// for exactly this situation (a spec element naming a destination this codebase
/// cannot yet build to, in an additive-only task that must not create a fake
/// `NavigationLink` to a screen that doesn't exist): render the note as inert,
/// non-interactive text with a comment explaining why, rather than either silently
/// dropping it or wiring a `NavigationLink(destination:)` that would crash or dead-end.
/// If `PrivacyView.swift` lands on `main` later, `privacyNote` below is the one place
/// to swap in a real `NavigationLink` to it.
struct ConnectCalendarView: View {
    @StateObject private var viewModel: ConnectCalendarViewModel

    /// - Parameters:
    ///   - calendarService: mirrors `RootView`'s `calendarService: CalendarHolding` —
    ///     injected as the protocol type so a preview or a test can substitute a
    ///     no-op/mock conformer instead of the real `EventKitCalendarService`.
    ///   - accountsState: the connected-accounts snapshot to start from. Defaults to
    ///     `.empty` (a brand-new, never-onboarded user, which is what this first-run
    ///     screen almost always sees) — a caller further along in onboarding that
    ///     already has a partial `ConnectedAccountsState` can pass it in instead so
    ///     this screen's transition builds on top of it rather than discarding it.
    ///   - onFinished: called exactly once — when calendar access is granted, denied,
    ///     or explicitly skipped — with the resulting `ConnectedAccountsState`.
    ///     Defaults to a no-op since wiring this screen into first-run navigation is a
    ///     later task; the caller that does that wiring passes a closure that advances
    ///     to the next first-run step and persists (or carries forward) the state.
    init(
        calendarService: CalendarHolding,
        accountsState: ConnectedAccountsState = .empty,
        onFinished: @escaping (ConnectedAccountsState) -> Void = { _ in }
    ) {
        _viewModel = StateObject(
            wrappedValue: ConnectCalendarViewModel(
                calendarService: calendarService,
                accountsState: accountsState,
                onFinished: onFinished
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("Connect calendar")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                Text("Clearsky holds protected time on your calendar for the promises you keep — one toggle, calendar only. Texts and email are never read here; they arrive by sharing into the app from the Share Sheet.")
                    .font(ClearskyFont.ui(15))
                    .foregroundStyle(ClearskyColor.body)
                    .fixedSize(horizontal: false, vertical: true)

                statusMessage

                privacyNote

                connectButton

                skipButton
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch viewModel.outcome {
        case .notDecided:
            EmptyView()
        case .granted:
            Text("Calendar connected.")
                .font(ClearskyFont.ui(13, weight: .medium))
                .foregroundStyle(ClearskyColor.keptGreen)
        case .skipped, .denied:
            Text("Skipped \u{2014} connect any time in Settings.")
                .font(ClearskyFont.ui(13, weight: .medium))
                .foregroundStyle(ClearskyColor.muted)
        }
    }

    /// Inert, non-interactive privacy note — see the type-level doc's "The privacy
    /// note" section for why this isn't a `NavigationLink` yet.
    private var privacyNote: some View {
        Text("Your calendar stays on-device and is never sold. Full privacy policy \u{2014} not available yet.")
            .font(ClearskyFont.ui(12))
            .foregroundStyle(ClearskyColor.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Privacy note: your calendar stays on-device and is never sold. Full privacy policy, not available yet.")
    }

    private var isResolved: Bool { viewModel.outcome != .notDecided }

    private var connectButton: some View {
        Button {
            Task { await viewModel.grantAccess() }
        } label: {
            Text(viewModel.isRequesting ? "Asking\u{2026}" : "Connect calendar")
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
        .disabled(isResolved || viewModel.isRequesting)
        .opacity(isResolved || viewModel.isRequesting ? 0.5 : 1)
    }

    private var skipButton: some View {
        Button {
            viewModel.skip()
        } label: {
            Text("Skip")
                .font(ClearskyFont.ui(15, weight: .medium))
                .foregroundStyle(ClearskyColor.secondaryInk)
                .frame(maxWidth: .infinity)
                .frame(minHeight: ClearskyMetric.minHitTarget)
        }
        .buttonStyle(.plain)
        .disabled(isResolved)
        .opacity(isResolved ? 0.5 : 1)
    }
}

/// The result of asking for calendar permission, as this screen tracks it. Deliberately
/// not a bare `Bool`: `.skipped` (the person explicitly skipped, never asking the OS)
/// and `.denied` (the OS request completed but came back `false`, or threw) both end in
/// "no calendar access granted", but this screen shows the same "connect any time in
/// Settings" copy for both while only `.skipped` skips the real ask entirely — kept as
/// two distinct cases (rather than collapsed into one) so a future copy change to only
/// one of them stays a one-line edit, the same reasoning
/// `NotificationPermissionOutcome` documents for its own `.declined`/`.denied` split.
enum ConnectCalendarOutcome: Equatable {
    case notDecided
    case granted
    case skipped
    case denied
}

/// Owns the grant/skip actions and their resulting state for `ConnectCalendarView` —
/// see the view's type-level doc for why this is a separate, directly-testable
/// `ObservableObject` rather than inline `@State` + methods on the view itself.
/// `ConnectCalendarViewModelTests` (in the test target) exercises this directly against
/// `MockCalendarService`.
@MainActor
final class ConnectCalendarViewModel: ObservableObject {
    @Published private(set) var outcome: ConnectCalendarOutcome = .notDecided
    @Published private(set) var isRequesting = false
    @Published private(set) var accountsState: ConnectedAccountsState

    private let calendarService: CalendarHolding
    private let onFinished: (ConnectedAccountsState) -> Void

    init(
        calendarService: CalendarHolding,
        accountsState: ConnectedAccountsState = .empty,
        onFinished: @escaping (ConnectedAccountsState) -> Void = { _ in }
    ) {
        self.calendarService = calendarService
        self.accountsState = accountsState
        self.onFinished = onFinished
    }

    /// Calls `calendarService.requestAccess()` — the one real ask at the OS. A no-op
    /// once `outcome` has already left `.notDecided`, so this screen can never ask
    /// twice in one session, mirroring `NotificationsPermissionViewModel.allow()`'s
    /// same guard.
    ///
    /// On a granted (`true`) result, applies `ConnectedAccountsTransition
    /// .apply(.connectAccount(.calendar), to:)` to the current `accountsState` and
    /// publishes the result. On denied (`false`, or a thrown error) applies no
    /// transition at all — `accountsState` is unchanged and `.calendar` never appears
    /// in `connectedAccountKinds`.
    func grantAccess() async {
        guard outcome == .notDecided else { return }
        isRequesting = true
        let granted: Bool
        do {
            granted = try await calendarService.requestAccess()
        } catch {
            granted = false
        }
        isRequesting = false
        if granted {
            accountsState = ConnectedAccountsTransition.apply(.connectAccount(.calendar), to: accountsState)
            outcome = .granted
        } else {
            outcome = .denied
        }
        onFinished(accountsState)
    }

    /// Skips without ever calling `calendarService` — this is the one place the
    /// spec's "skippable" requirement is honored with no OS prompt at all. Applies no
    /// transition, so `accountsState` passes through unchanged. A no-op once `outcome`
    /// has already left `.notDecided`, same guard as `grantAccess()`.
    func skip() {
        guard outcome == .notDecided else { return }
        outcome = .skipped
        onFinished(accountsState)
    }
}

// MARK: - Preview

/// A no-op `CalendarHolding` for previews only — never shows a real EventKit
/// permission alert, so a preview run never attempts a real `EKEventStore` call. Same
/// pattern as `RootView.swift`'s private `PreviewCalendarService`.
private struct PreviewConnectCalendarService: CalendarHolding {
    let granted: Bool
    func requestAccess() async throws -> Bool { granted }
    func createHold(for block: ProtectedTimeBlock) async throws -> String { "preview-event" }
    func removeHold(eventIdentifier: String) async throws {}
}

#Preview("Not decided \u{2014} would grant") {
    ConnectCalendarView(calendarService: PreviewConnectCalendarService(granted: true))
}

#Preview("Not decided \u{2014} would deny") {
    ConnectCalendarView(calendarService: PreviewConnectCalendarService(granted: false))
}
