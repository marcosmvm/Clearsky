import SwiftUI

/// The "Notifications" first-run screen.
///
/// Per `01 Product Scope.dc.html` §6 Screen inventory, "Notifications" — Purpose:
/// "Ask for permission and set the expectation". Key states/actions: "Allow or
/// decline; declining is respected everywhere and shown in Settings." §7 flow A
/// places this screen last in first run, right before Today: "Sign in → connect
/// calendar → pick inner circle → notification permission → Today. Every step is
/// skippable except sign-in." This file builds the screen itself only — wiring it
/// into that real first-run navigation order is a later, separate task (this
/// screen's own task note is explicit that navigation wiring is out of scope here,
/// specifically so it doesn't collide with other in-flight edits to `RootView.swift`).
///
/// §8 Notifications is the "expectation" this screen states honestly: exactly three
/// notification categories exist in V1, matching the closed vocabulary
/// `ClearskyCore.NotificationBudget.swift`'s `NotificationCategory` enum encodes in
/// code (`morningSummary`, `duePromiseReminder`, `sundayRecap`) — "Morning summary",
/// "Promise due" and "Weekly recap" below use that same vocabulary and the same
/// once-a-day/once-a-week limits that file documents, not new wording invented here.
/// This screen deliberately does not let the person configure each one individually
/// (no per-notification toggles) — §6 assigns that to the "You"/Settings screen,
/// out of scope here.
///
/// ## Why the permission ask is a view model, not inline `@State` on the view
///
/// `allow()`/`decline()` are pulled into `NotificationsPermissionViewModel`, a plain
/// `ObservableObject`, rather than living as `@State` + methods directly on
/// `NotificationsPermissionView`, so a test can drive them against an injected
/// `MockNotificationPermissionService` directly — the same reasoning `PromiseStore`
/// (also a plain, directly-testable `ObservableObject`) already follows elsewhere in
/// this target, rather than reaching for SwiftUI-view-inspection machinery this
/// project has no dependency on.
struct NotificationsPermissionView: View {
    @StateObject private var viewModel: NotificationsPermissionViewModel

    /// - Parameters:
    ///   - permissionService: mirrors `RootView`'s `calendarService: CalendarHolding`
    ///     — injected as the protocol type so a preview or a test can substitute a
    ///     no-op/mock conformer instead of the real
    ///     `SystemNotificationPermissionService`.
    ///   - onFinished: called exactly once — when the person allows, is denied, or
    ///     explicitly declines — with whether notifications ended up granted. Defaults
    ///     to a no-op since wiring this screen into first-run navigation is a later
    ///     task; the caller that does that wiring passes a closure that advances to
    ///     Today.
    init(
        permissionService: NotificationPermissionRequesting,
        onFinished: @escaping (Bool) -> Void = { _ in }
    ) {
        _viewModel = StateObject(
            wrappedValue: NotificationsPermissionViewModel(
                permissionService: permissionService,
                onFinished: onFinished
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("Notifications")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                Text("Clearsky sends three notifications, never a fourth. Allow them and here is exactly what that unlocks — decline and it stays quiet everywhere, a choice Settings always shows and you can change any time.")
                    .font(ClearskyFont.ui(15))
                    .foregroundStyle(ClearskyColor.body)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: ClearskySpacing.xs) {
                    NotificationExpectationRow(
                        title: "Morning summary",
                        detail: "8:00 each morning \u{2014} the size of the stack and the most urgent promise, one line."
                    )
                    NotificationExpectationRow(
                        title: "Promise due",
                        detail: "Only the day it's due, only once \u{2014} never for a promise with no date."
                    )
                    NotificationExpectationRow(
                        title: "Weekly recap",
                        detail: "Sunday evening \u{2014} what you kept, what moved, and the one thing to watch."
                    )
                }

                statusMessage

                allowButton

                declineButton
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
            Text("Notifications on.")
                .font(ClearskyFont.ui(13, weight: .medium))
                .foregroundStyle(ClearskyColor.keptGreen)
        case .declined, .denied:
            Text("Skipped \u{2014} turn this on any time in Settings.")
                .font(ClearskyFont.ui(13, weight: .medium))
                .foregroundStyle(ClearskyColor.muted)
        }
    }

    private var isResolved: Bool { viewModel.outcome != .notDecided }

    private var allowButton: some View {
        Button {
            Task { await viewModel.allow() }
        } label: {
            Text(viewModel.isRequesting ? "Asking\u{2026}" : "Allow notifications")
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

    private var declineButton: some View {
        Button {
            viewModel.decline()
        } label: {
            Text("Not now")
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

/// One row in the "what this unlocks" list — a title plus the honest, specific detail
/// behind it. Deliberately not a toggle: §6 assigns per-notification configuration to
/// the "You"/Settings screen, out of scope here.
private struct NotificationExpectationRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(ClearskyFont.ui(15, weight: .semibold))
                .foregroundStyle(ClearskyColor.inkNavy)
            Text(detail)
                .font(ClearskyFont.ui(13))
                .foregroundStyle(ClearskyColor.muted)
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
    }
}

/// The result of asking for notification permission, as this screen tracks it.
/// Deliberately not a bare `Bool`: `.declined` (the person explicitly said not now,
/// never asking the OS) and `.denied` (the OS request completed but came back
/// `false`, or threw) both end in "no permission granted", but this screen shows
/// different copy for each, and only `.declined` skips the real ask entirely.
enum NotificationPermissionOutcome: Equatable {
    case notDecided
    case granted
    case declined
    case denied
}

/// Owns the allow/decline actions and their resulting state for
/// `NotificationsPermissionView` — see the view's type-level doc for why this is a
/// separate, directly-testable `ObservableObject` rather than inline `@State` +
/// methods on the view itself. `NotificationsPermissionViewModelTests` (in the test
/// target) exercises this directly against `MockNotificationPermissionService`.
@MainActor
final class NotificationsPermissionViewModel: ObservableObject {
    @Published private(set) var outcome: NotificationPermissionOutcome = .notDecided
    @Published private(set) var isRequesting = false

    private let permissionService: NotificationPermissionRequesting
    private let onFinished: (Bool) -> Void

    init(
        permissionService: NotificationPermissionRequesting,
        onFinished: @escaping (Bool) -> Void = { _ in }
    ) {
        self.permissionService = permissionService
        self.onFinished = onFinished
    }

    /// Calls `permissionService.requestAccess()` — the one real ask at the OS. A
    /// no-op once `outcome` has already left `.notDecided`, so this screen can never
    /// ask twice in one session: the spec's "declining is respected everywhere"
    /// promise only holds if a repeat call here can't re-trigger the OS prompt after
    /// the person already answered once.
    func allow() async {
        guard outcome == .notDecided else { return }
        isRequesting = true
        let granted: Bool
        do {
            granted = try await permissionService.requestAccess()
        } catch {
            granted = false
        }
        isRequesting = false
        outcome = granted ? .granted : .denied
        onFinished(granted)
    }

    /// Declines without ever calling `permissionService` — this is the one place the
    /// spec's "Allow or decline" choice is honored with no OS prompt at all. A no-op
    /// once `outcome` has already left `.notDecided`, same guard as `allow()`.
    func decline() {
        guard outcome == .notDecided else { return }
        outcome = .declined
        onFinished(false)
    }
}

// MARK: - Preview

/// A no-op `NotificationPermissionRequesting` for previews only — never shows a real
/// OS permission alert, so a preview run never attempts a real
/// `UNUserNotificationCenter` call. Same pattern as `RootView.swift`'s private
/// `PreviewCalendarService`.
private struct PreviewNotificationPermissionService: NotificationPermissionRequesting {
    let granted: Bool
    func requestAccess() async throws -> Bool { granted }
}

#Preview("Not decided \u{2014} would grant") {
    NotificationsPermissionView(permissionService: PreviewNotificationPermissionService(granted: true))
}

#Preview("Not decided \u{2014} would deny") {
    NotificationsPermissionView(permissionService: PreviewNotificationPermissionService(granted: false))
}
