import SwiftUI
import ClearskyCore

/// The real, first-run screen sequence a brand-new install shows before it ever lands
/// on `RootView`'s three-tab shell.
///
/// Per root `README.md`'s "Screens" section and `01 Product Scope.dc.html` §7 flow A,
/// the full first-run order is: "Sign in → connect calendar → pick inner circle →
/// notification permission → Today. Every step is skippable except sign-in." Two of
/// those four steps do not exist in this codebase yet and are out of scope for this
/// task: Sign in needs an Apple Developer capability that has not been enabled on the
/// account yet, and Inner circle needs a new `Person` domain model plus a Contacts
/// integration that has not been built. This view wires the two steps that *do*
/// already exist — `ConnectCalendarView` and `NotificationsPermissionView`, both built
/// and tested earlier this shift — into the real sequence a fresh install shows:
/// connect calendar, then notification permission, then `onFinished()` hands control
/// back to the caller (`ClearskyApp.swift`), which lands on Today by flipping
/// `hasCompletedFirstRun` and showing `RootView`.
///
/// ## Why this view owns `calendarConnected`/`notificationsGranted` via `@AppStorage`
///
/// Both screens already report their own outcome through `onFinished` (`(state:
/// ConnectedAccountsState) -> Void` and `(granted: Bool) -> Void` respectively), but
/// neither screen persists that outcome anywhere — by design, per each file's own doc
/// comment, since navigation/persistence wiring was explicitly out of scope when they
/// were built. This view is that wiring: it reduces `ConnectedAccountsState` down to
/// the one bit another in-flight screen (built in parallel this same round) needs —
/// `state.hasAnyConnectedAccount` — and reduces the notification outcome down to the
/// `Bool` it already is, persisting both to `UserDefaults` under the exact key strings
/// `"calendarConnected"` and `"notificationsGranted"` so that other screen can read
/// them back later without this view or that one needing to share any other state.
///
/// ## Why `step` is plain `@State`, not a view model
///
/// There is no async action or testable business logic living on this view itself —
/// both real actions (`grantAccess()`/`allow()`) already live on `ConnectCalendarViewModel`
/// and `NotificationsPermissionViewModel` inside the screens this view only sequences.
/// `FirstRunFlowView`'s own job is exactly two lines of `Step` transition logic, which
/// `FirstRunFlowViewTests` exercises directly against the same `MockCalendarService`/
/// `MockNotificationPermissionService` those screens' own tests already use — no
/// `ObservableObject` needed for that, per this repo's own "no view model unless there's
/// an async action or non-trivial computation to isolate" convention (see
/// `DigestCalculator` for the plain-value-type version of the same judgment call).
struct FirstRunFlowView: View {
    /// The two first-run steps this codebase can build today. Sign-in and Inner circle
    /// are deliberately absent — see the type-level doc comment.
    enum Step {
        case connectCalendar
        case notifications
    }

    @State private var step: Step

    private let calendarService: CalendarHolding
    private let notificationPermissionService: NotificationPermissionRequesting
    private let onFinished: () -> Void

    /// Whether the person has connected at least one calendar account. Read by another
    /// first-run screen built in parallel this round — the key string must stay
    /// exactly `"calendarConnected"`.
    @AppStorage("calendarConnected") private var calendarConnected = false

    /// Whether notification permission ended up granted (as opposed to declined or
    /// denied). Not currently read anywhere else, but kept alongside
    /// `calendarConnected` for the same reason: the outcome of a skippable first-run
    /// step should survive past the screen that produced it.
    @AppStorage("notificationsGranted") private var notificationsGranted = false

    /// - Parameters:
    ///   - calendarService: forwarded to `ConnectCalendarView` — see that type's own
    ///     `init` doc for why this is the protocol type, not the concrete
    ///     `EventKitCalendarService`.
    ///   - notificationPermissionService: forwarded to `NotificationsPermissionView` —
    ///     same reasoning as `calendarService` above.
    ///   - onFinished: called exactly once, after the notifications step resolves
    ///     (allowed, denied, or declined) — the caller (`ClearskyApp.swift`) uses this
    ///     to flip `hasCompletedFirstRun` and show `RootView`.
    init(
        calendarService: CalendarHolding,
        notificationPermissionService: NotificationPermissionRequesting,
        onFinished: @escaping () -> Void
    ) {
        self.calendarService = calendarService
        self.notificationPermissionService = notificationPermissionService
        self.onFinished = onFinished
        _step = State(initialValue: .connectCalendar)
    }

    var body: some View {
        switch step {
        case .connectCalendar:
            ConnectCalendarView(
                calendarService: calendarService,
                onFinished: { state in
                    calendarConnected = state.hasAnyConnectedAccount
                    step = .notifications
                }
            )
        case .notifications:
            NotificationsPermissionView(
                permissionService: notificationPermissionService,
                onFinished: { granted in
                    notificationsGranted = granted
                    onFinished()
                }
            )
        }
    }
}

// MARK: - Preview

/// No-op `CalendarHolding`/`NotificationPermissionRequesting` conformers for previews
/// only — mirrors `ConnectCalendarView.swift`'s `PreviewConnectCalendarService` and
/// `NotificationsPermissionView.swift`'s `PreviewNotificationPermissionService`. Each of
/// those types is `private` to its own file, so this file builds its own rather than
/// importing them, per this project's established preview pattern.
private struct PreviewFirstRunCalendarService: CalendarHolding {
    let granted: Bool
    func requestAccess() async throws -> Bool { granted }
    func createHold(for block: ProtectedTimeBlock) async throws -> String { "preview-event" }
    func removeHold(eventIdentifier: String) async throws {}
}

private struct PreviewFirstRunNotificationService: NotificationPermissionRequesting {
    let granted: Bool
    func requestAccess() async throws -> Bool { granted }
}

#Preview("First run \u{2014} connect calendar") {
    FirstRunFlowView(
        calendarService: PreviewFirstRunCalendarService(granted: true),
        notificationPermissionService: PreviewFirstRunNotificationService(granted: true),
        onFinished: {}
    )
}
