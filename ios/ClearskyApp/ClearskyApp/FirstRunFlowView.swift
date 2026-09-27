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
/// named by `FirstRunDefaultsKey` (`FirstRunDefaultsKey.swift`) so that other screen
/// can read them back later without this view or that one needing to share any other
/// state.
///
/// ## Why `step` is plain `@State`, not a view model
///
/// There is no async action or testable business logic living on this view itself —
/// both real actions (`grantAccess()`/`allow()`) already live on `ConnectCalendarViewModel`
/// and `NotificationsPermissionViewModel` inside the screens this view only sequences.
/// `FirstRunFlowView`'s own job is exactly two lines of `Step` transition logic, pulled
/// into `handleConnectCalendarFinished(_:)`/`handleNotificationsFinished(_:)` below
/// (rather than left as the inline closures an earlier version of this file used) so a
/// test can trigger the *exact* method `body` wires up, not a hand-copied
/// reimplementation of it. No `ObservableObject` needed here, per this repo's own "no
/// view model unless there's an async action or non-trivial computation to isolate"
/// convention (see `DigestCalculator` for the plain-value-type version of the same
/// judgment call).
///
/// ## How `FirstRunFlowViewTests` actually proves `step` advances
///
/// This environment has no touch-injection tool (`idb` is not installed, `xcrun simctl`
/// has no tap/gesture command) and — confirmed empirically while building this fix —
/// SwiftUI does not materialize any `UIAccessibilityContainer` elements for a view
/// hosted with no real assistive-technology client attached (`accessibilityElementCount()`
/// stays `0` on the hosted `_UIHostingView` no matter how long a real layout pass is
/// pumped), so `accessibilityActivate()` cannot invoke a button's action here either.
/// There is therefore no way to make a real tap land on `ConnectCalendarView`'s "Skip"
/// button from an XCTest in this environment. `testHooks` (`FirstRunFlowViewTestHooks`,
/// below) is the resulting, deliberately narrow instrumentation point: always `nil` at
/// every real call site, and reported into via `.onAppear` — which runs during a real,
/// live SwiftUI render pass, so the `handleConnectCalendarFinished`/
/// `handleNotificationsFinished` closures it captures are the actually-bound methods on
/// the live, graph-installed view (not a disconnected copy — see
/// `FirstRunFlowViewTestHooks`'s own doc comment for why this specific mechanism is
/// sound where reading `@State` back through `UIHostingController.rootView` is not,
/// per the `clearsky-ios-build-conventions` agent memory's finding from PR #30). A test
/// calls `testHooks.triggerConnectCalendarFinished`/`triggerNotificationsFinished`
/// directly — the real production methods, invoked on the real hosted instance — and
/// confirms `testHooks.currentStep` actually advances to `.notifications` as a result,
/// which is exactly the assignment a "delete `step`'s advancement" mutation removes.
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
    /// first-run screen built in parallel this round — the key string comes from
    /// `FirstRunDefaultsKey.calendarConnected`, which must stay exactly
    /// `"calendarConnected"` (see that enum's own doc comment).
    @AppStorage(FirstRunDefaultsKey.calendarConnected) private var calendarConnected = false

    /// Whether notification permission ended up granted (as opposed to declined or
    /// denied). Not currently read anywhere else, but kept alongside
    /// `calendarConnected` for the same reason: the outcome of a skippable first-run
    /// step should survive past the screen that produced it.
    @AppStorage(FirstRunDefaultsKey.notificationsGranted) private var notificationsGranted = false

    /// Always `nil` at every real call site (`ClearskyApp.swift`/`RootRouterView` never
    /// passes one) — see the type-level doc's "How `FirstRunFlowViewTests` actually
    /// proves `step` advances" section and `FirstRunFlowViewTestHooks`'s own doc comment
    /// for why this specific, narrow instrumentation point exists and how it's sound.
    var testHooks: FirstRunFlowViewTestHooks?

    /// - Parameters:
    ///   - calendarService: forwarded to `ConnectCalendarView` — see that type's own
    ///     `init` doc for why this is the protocol type, not the concrete
    ///     `EventKitCalendarService`.
    ///   - notificationPermissionService: forwarded to `NotificationsPermissionView` —
    ///     same reasoning as `calendarService` above.
    ///   - defaults: the `UserDefaults` store `calendarConnected`/`notificationsGranted`
    ///     read and write. Defaults to `.standard` — the real app's shared defaults —
    ///     so the real call site (`ClearskyApp.swift`, via `RootRouterView`) behaves
    ///     exactly as before this parameter existed. A test hosts this view with a
    ///     disposable, suite-backed instance instead (the same injectable-`@AppStorage`
    ///     pattern `YouView.swift` already uses, via each property's own
    ///     `_property = AppStorage(wrappedValue:_:store:)` override in `init` below),
    ///     so it never reads or writes the real app's shared defaults and can assert
    ///     on the exact instance it handed in without touching global state.
    ///   - testHooks: see that property's own doc comment. Always `nil` at every real
    ///     call site.
    ///   - onFinished: called exactly once, after the notifications step resolves
    ///     (allowed, denied, or declined) — the caller (`ClearskyApp.swift`) uses this
    ///     to flip `hasCompletedFirstRun` and show `RootView`.
    init(
        calendarService: CalendarHolding,
        notificationPermissionService: NotificationPermissionRequesting,
        defaults: UserDefaults = .standard,
        testHooks: FirstRunFlowViewTestHooks? = nil,
        onFinished: @escaping () -> Void
    ) {
        self.calendarService = calendarService
        self.notificationPermissionService = notificationPermissionService
        self.testHooks = testHooks
        self.onFinished = onFinished
        _step = State(initialValue: .connectCalendar)
        _calendarConnected = AppStorage(
            wrappedValue: false,
            FirstRunDefaultsKey.calendarConnected,
            store: defaults
        )
        _notificationsGranted = AppStorage(
            wrappedValue: false,
            FirstRunDefaultsKey.notificationsGranted,
            store: defaults
        )
    }

    var body: some View {
        switch step {
        case .connectCalendar:
            ConnectCalendarView(
                calendarService: calendarService,
                onFinished: handleConnectCalendarFinished
            )
            .onAppear {
                testHooks?.currentStep = .connectCalendar
                testHooks?.triggerConnectCalendarFinished = handleConnectCalendarFinished
            }
        case .notifications:
            NotificationsPermissionView(
                permissionService: notificationPermissionService,
                onFinished: handleNotificationsFinished
            )
            .onAppear {
                testHooks?.currentStep = .notifications
                testHooks?.triggerNotificationsFinished = handleNotificationsFinished
            }
        }
    }

    /// `ConnectCalendarView`'s real `onFinished` — the only place `step` advances past
    /// `.connectCalendar`. Kept `private`: only the type-erased closure reference
    /// crosses into `FirstRunFlowViewTestHooks`, not this method itself, so
    /// encapsulation is unchanged from before this method had a name.
    private func handleConnectCalendarFinished(_ state: ConnectedAccountsState) {
        calendarConnected = state.hasAnyConnectedAccount
        step = .notifications
    }

    /// `NotificationsPermissionView`'s real `onFinished` — the only place `onFinished()`
    /// (this view's own, to `ClearskyApp`/`RootRouterView`) is called. Kept `private`,
    /// same reasoning as `handleConnectCalendarFinished(_:)` above.
    private func handleNotificationsFinished(_ granted: Bool) {
        notificationsGranted = granted
        onFinished()
    }
}

/// Test-only observation/trigger hooks for `FirstRunFlowView` — always `nil` in every
/// real (non-test) `FirstRunFlowView` value. See `FirstRunFlowView`'s own "How
/// `FirstRunFlowViewTests` actually proves `step` advances" doc section for the full
/// reasoning; this comment covers this specific type's contract.
///
/// `currentStep` and the two `trigger...` closures are all set from inside
/// `FirstRunFlowView.body`'s `.onAppear` callbacks — i.e. during a real, live SwiftUI
/// render pass, after the framework has already bound this view's `@State`/`@AppStorage`
/// storage to its position in the view graph. Capturing `handleConnectCalendarFinished`/
/// `handleNotificationsFinished` at that moment (rather than obtaining them some other
/// way, e.g. via `UIHostingController.rootView`, which returns whatever value was last
/// explicitly assigned to it rather than the live render-tree state — see the
/// `clearsky-ios-build-conventions` agent memory's PR #30 finding) means the closures
/// this class hands back to a test are bound to the *actual* installed `@State` storage:
/// calling `triggerConnectCalendarFinished` genuinely advances the hosted view's real
/// `step`, and a subsequent render reports that back through `currentStep` via the next
/// `.onAppear` — the same "plain closure into a class the test owns" mechanism
/// `PromisesViewNavigationTests.swift`'s `onRowFramesChanged` already uses in this
/// codebase for the mirror-image problem (reading state out instead of triggering
/// behavior in).
///
/// This is a `class`, not a `struct`: `FirstRunFlowView` holds it as a plain `var`
/// (not `@State`), so mutations by one copy of the view value must be visible to every
/// other copy (including the one a test constructed) without any of `@State`'s
/// installation requirements — a reference type is what makes that true.
final class FirstRunFlowViewTestHooks {
    var currentStep: FirstRunFlowView.Step?
    var triggerConnectCalendarFinished: ((ConnectedAccountsState) -> Void)?
    var triggerNotificationsFinished: ((Bool) -> Void)?

    init() {}
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
