import XCTest
import SwiftUI
import ClearskyCore
@testable import ClearskyApp

// MARK: - FirstRunDefaultsKeyTests

/// Pins the exact `UserDefaults` key string literals `FirstRunDefaultsKey` exposes.
///
/// Deliberately hard-coded literals on the right-hand side of each assertion (not,
/// say, `FirstRunDefaultsKey.calendarConnected == FirstRunDefaultsKey.calendarConnected`,
/// which would trivially always pass no matter what the constant's value is) — the
/// whole point is to catch a future edit to `FirstRunDefaultsKey.swift` that changes
/// one of these strings, since `"calendarConnected"` in particular is also depended on
/// by a different screen in a different file (`YouView.swift`'s own
/// `YouViewDefaultsKey.calendarConnected`) that this test target cannot see or assert
/// against directly.
final class FirstRunDefaultsKeyTests: XCTestCase {
    func testExactKeyStringValues() {
        XCTAssertEqual(FirstRunDefaultsKey.calendarConnected, "calendarConnected")
        XCTAssertEqual(FirstRunDefaultsKey.notificationsGranted, "notificationsGranted")
        XCTAssertEqual(FirstRunDefaultsKey.hasCompletedFirstRun, "hasCompletedFirstRun")
    }
}

// MARK: - RootRouterViewTests

/// Proves `RootRouterView`'s `hasCompletedFirstRun` branch actually renders different
/// content for each value — the branch `ClearskyApp.swift` used to have inline, where
/// it was untestable (an `App`/`Scene` cannot be hosted in an XCTest, only a `View`
/// can). Mutation testing proved the untestable branch was a real gap: forcing
/// `ClearskyApp`'s old inline `if hasCompletedFirstRun { RootView } else {
/// FirstRunFlowView }` to always take the `RootView` branch left every existing test
/// green, because nothing exercised it.
///
/// ## How this tells `RootView` and `FirstRunFlowView` apart without ViewInspector/XCUITest
///
/// Neither screen's own `Text`/`Button` content becomes a real `UIView` — SwiftUI
/// renders simple content as `CGDrawingLayer`s with no meaningful UIKit subview to
/// search for (confirmed by dumping the hosted view hierarchy while building this fix:
/// `ConnectCalendarView`, hosted directly, has exactly one real UIKit descendant beyond
/// scaffolding, `HostingScrollView` — a genuine `UIScrollView` subclass, since
/// `ScrollView` is one of the SwiftUI containers that does bridge to a real UIKit type).
/// `RootView`'s `TabView`, specifically, is *also* one of those bridging containers — it
/// is backed by a real `UITabBar` in the hosted view hierarchy, which `FirstRunFlowView`
/// (a plain `ScrollView`, no `TabView` anywhere in it or in either first-run screen it
/// shows) never produces. Searching the hosted hierarchy for a `UITabBar` is therefore a
/// real, structural signal — not a guess or a snapshot-pixel comparison — of which branch
/// actually rendered.
@MainActor
final class RootRouterViewTests: XCTestCase {
    private var window: UIWindow!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("duck-test-root-router-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        super.tearDown()
    }

    /// Hosts `view` in a real `UIWindow`/`UIHostingController`, makes it key and
    /// visible, and forces a real layout pass — the same technique
    /// `PromisesViewNavigationTests.swift` (PR #30) established for this codebase.
    @discardableResult
    private func host<V: View>(_ view: V) -> UIHostingController<V> {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        self.window = window
        return controller
    }

    /// Pumps the run loop in short bursts for up to `seconds`, giving SwiftUI's own
    /// scroll-view/tab-bar bridging time to materialize after the initial layout pass —
    /// `PromisesViewNavigationTests.swift`'s `waitUntil` documents the same need for
    /// `PreferenceKey` propagation; this is the fixed-duration version of it, since
    /// there is no single boolean condition to poll for here (the assertion itself is
    /// "absent" for one branch).
    private func pump(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func containsTabBar(_ view: UIView) -> Bool {
        if view is UITabBar { return true }
        for subview in view.subviews where containsTabBar(subview) {
            return true
        }
        return false
    }

    private func makeRouterDependencies() -> (PromiseStore, SharedDraftStoreObserver) {
        let promiseStore = PromiseStore(fileURL: fileURL)
        let suiteName = "duck-test-root-router-drafts-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let draftsObserver = SharedDraftStoreObserver(
            store: SharedDraftStore(defaults: defaults),
            defaults: defaults
        )
        return (promiseStore, draftsObserver)
    }

    func testHasCompletedFirstRunTrueRendersRootViewsRealTabBar() {
        let (promiseStore, draftsObserver) = makeRouterDependencies()
        let view = RootRouterView(
            hasCompletedFirstRun: true,
            promiseStore: promiseStore,
            draftsObserver: draftsObserver,
            calendarService: MockCalendarService(),
            notificationPermissionService: MockNotificationPermissionService(),
            onFirstRunFinished: {}
        )
        let controller = host(view)
        pump(0.5)

        XCTAssertTrue(
            containsTabBar(controller.view),
            "hasCompletedFirstRun: true should render RootView, whose TabView bridges to a real UITabBar"
        )
    }

    func testHasCompletedFirstRunFalseRendersFirstRunFlowViewWithNoTabBar() {
        let (promiseStore, draftsObserver) = makeRouterDependencies()
        let view = RootRouterView(
            hasCompletedFirstRun: false,
            promiseStore: promiseStore,
            draftsObserver: draftsObserver,
            calendarService: MockCalendarService(),
            notificationPermissionService: MockNotificationPermissionService(),
            onFirstRunFinished: {}
        )
        let controller = host(view)
        pump(0.5)

        XCTAssertFalse(
            containsTabBar(controller.view),
            "hasCompletedFirstRun: false should render FirstRunFlowView (no TabView anywhere in it), never a UITabBar"
        )
    }
}

// MARK: - FirstRunFlowViewTests

/// Exercises `FirstRunFlowView`'s own job: advancing `step` from `.connectCalendar` to
/// `.notifications` and persisting the right `Bool` to `UserDefaults` under
/// `FirstRunDefaultsKey.calendarConnected`/`.notificationsGranted` — by hosting the real
/// view in a live `UIWindow` and triggering its real, production `onFinished` methods,
/// not a hand-copied re-implementation of them.
///
/// ## Why the previous version of this file was wrong
///
/// The previous test built its own, separate `ConnectCalendarViewModel`/
/// `NotificationsPermissionViewModel` instances with hand-rewritten `onFinished`
/// closures that copied `FirstRunFlowView`'s reduction logic (`state in
/// UserDefaults.standard.set(state.hasAnyConnectedAccount, forKey: ...)`) instead of
/// exercising `FirstRunFlowView` itself. Mutation testing proved this was vacuous:
/// deleting `step`'s advancement from the real view, breaking the `"calendarConnected"`
/// key string, and disabling the `hasCompletedFirstRun`-gated branch in
/// `ClearskyApp.swift` all left every one of those 6 tests passing, since none of them
/// ever ran a single line of `FirstRunFlowView.swift`.
///
/// ## Why hosting + `accessibilityActivate()` (the sibling PR #30 technique) does not
/// work here, and what does instead
///
/// `PromisesViewNavigationTests.swift` (PR #30) hosts `PromisesView` in a real
/// `UIWindow` and reads real `GeometryReader`-computed frames back out through a plain
/// closure — proving layout, not interaction. This screen's defect is specifically
/// about interaction (does tapping a button really advance `step`?), so simply copying
/// that pattern isn't enough on its own. Two candidate ways to simulate a real tap were
/// tried and ruled out empirically while building this fix:
///
/// 1. **Touch injection** — there is no touch-injection tool in this environment
///    (`idb`/`idb_companion` is not installed; `xcrun simctl` has no tap/gesture
///    command), and `UITouch` has no public initializer, so no `UIGestureRecognizer`
///    can be driven with a fabricated touch either.
/// 2. **`accessibilityActivate()`** — the mechanism VoiceOver uses to invoke a SwiftUI
///    button's action, callable directly without a touch. Confirmed NOT to work here:
///    dumping the hosted view hierarchy shows SwiftUI renders `ConnectCalendarView`'s
///    content as `CGDrawingLayer`s with zero real UIKit subviews for its buttons, and
///    `controller.view.accessibilityElementCount()` stays `0` no matter how long a real
///    layout pass is pumped — SwiftUI does not appear to materialize its
///    `UIAccessibilityContainer` tree at all without a real assistive-technology client
///    (e.g. VoiceOver) attached to the process, which nothing in this test host provides.
///
/// With both ruled out, this file uses `FirstRunFlowView.testHooks`
/// (`FirstRunFlowViewTestHooks`) instead — see that type's own doc comment for the full
/// mechanism. In short: `body`'s `.onAppear` callbacks (which run during a real, live
/// SwiftUI render pass, after the framework has bound this view's `@State`/`@AppStorage`
/// storage to its position in the graph) capture `FirstRunFlowView`'s actual, private
/// `handleConnectCalendarFinished(_:)`/`handleNotificationsFinished(_:)` methods — the
/// same methods `body` passes as each child screen's real `onFinished` — into
/// `testHooks`. Calling `testHooks.triggerConnectCalendarFinished`/
/// `triggerNotificationsFinished` from a test therefore invokes the exact production
/// method on the exact live, graph-bound view instance: not a duplicate, and not a
/// disconnected copy (reading `@State` back through `UIHostingController.rootView`,
/// ruled out for the same "disconnected copy" reason during PR #30's own follow-up
/// round — see the `clearsky-ios-build-conventions` agent memory).
///
/// This proves the actual wiring `ConnectCalendarView`/`NotificationsPermissionView`'s
/// real `onFinished` closures are attached to. It does not, on its own, prove that a
/// real finger tap on "Skip"/"Connect calendar"/"Allow notifications" reaches that
/// closure — that link is `ConnectCalendarViewModel.grantAccess()`/`skip()` and
/// `NotificationsPermissionViewModel.allow()`/`decline()` calling the `onFinished`
/// closure they were constructed with, which `ConnectCalendarViewModelTests.swift`/
/// `NotificationsPermissionViewModelTests.swift` already prove independently (unchanged
/// by this task), plus `ConnectCalendarView`/`NotificationsPermissionView` forwarding
/// their `init`'s `onFinished` parameter straight through to their view model with no
/// transformation (a one-line pass-through in each file, neither of which this task is
/// scoped to touch or re-test). Together, those two already-proven links plus this
/// file's proof of `FirstRunFlowView`'s own reduction cover the full chain from a real
/// tap to a real `UserDefaults` write, with no step re-implemented by hand anywhere in
/// the chain.
@MainActor
final class FirstRunFlowViewTests: XCTestCase {
    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Hosts `view` in a real `UIWindow`/`UIHostingController`, makes it key and
    /// visible, and forces a real layout pass — see this file's own type-level doc for
    /// why this (plus `testHooks`) is necessary, rather than optional.
    @discardableResult
    private func host<V: View>(_ view: V) -> UIHostingController<V> {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        self.window = window
        return controller
    }

    /// Pumps the run loop in short bursts until `condition` is true or `timeout`
    /// elapses — SwiftUI's re-render after a `@State` write is not guaranteed
    /// synchronous with the write, matching `PromisesViewNavigationTests.swift`'s own
    /// `waitUntil` and its documented reasoning.
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func makeHostedFlow(
        calendarService: CalendarHolding = MockCalendarService(),
        notificationPermissionService: NotificationPermissionRequesting = MockNotificationPermissionService(),
        onFinished: @escaping () -> Void = {}
    ) -> (defaults: UserDefaults, hooks: FirstRunFlowViewTestHooks, controller: UIHostingController<FirstRunFlowView>) {
        let suiteName = "duck-test-first-run-flow-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let hooks = FirstRunFlowViewTestHooks()
        let view = FirstRunFlowView(
            calendarService: calendarService,
            notificationPermissionService: notificationPermissionService,
            defaults: defaults,
            testHooks: hooks,
            onFinished: onFinished
        )
        let controller = host(view)
        waitUntil { hooks.currentStep == .connectCalendar }
        return (defaults, hooks, controller)
    }

    // MARK: - Initial render

    func testInitialRenderShowsConnectCalendarStep() {
        let (_, hooks, _) = makeHostedFlow()
        XCTAssertEqual(hooks.currentStep, .connectCalendar)
        XCTAssertNotNil(hooks.triggerConnectCalendarFinished, "Expected the real handleConnectCalendarFinished method to be captured on the first render")
    }

    // MARK: - Connect calendar step's real advancement

    func testConnectedCalendarAdvancesToNotificationsAndPersistsCalendarConnectedTrue() {
        let (defaults, hooks, _) = makeHostedFlow()

        // The real state ConnectCalendarViewModel.grantAccess() would publish on a
        // granted request — ConnectCalendarViewModelTests.swift already proves the
        // view model produces exactly this given a granted MockCalendarService; this
        // test's job is only to prove FirstRunFlowView's own reduction of it.
        hooks.triggerConnectCalendarFinished?(ConnectedAccountsState(connectedAccountKinds: [.calendar]))

        waitUntil { hooks.currentStep == .notifications }
        XCTAssertEqual(hooks.currentStep, .notifications, "step should really advance once the real onFinished callback fires")
        XCTAssertTrue(defaults.bool(forKey: FirstRunDefaultsKey.calendarConnected))
    }

    func testSkippedOrDeniedCalendarAdvancesToNotificationsAndPersistsCalendarConnectedFalse() {
        let (defaults, hooks, _) = makeHostedFlow()

        // The real state both ConnectCalendarViewModel.skip() (never asks the OS) and
        // a denied grantAccess() (asks, comes back false) leave unchanged — `.empty`,
        // per ConnectCalendarViewModelTests.swift's own coverage of both paths.
        hooks.triggerConnectCalendarFinished?(.empty)

        waitUntil { hooks.currentStep == .notifications }
        XCTAssertEqual(hooks.currentStep, .notifications, "step should still advance even when no account was connected")
        XCTAssertFalse(defaults.bool(forKey: FirstRunDefaultsKey.calendarConnected))
    }

    // MARK: - Notifications step's real advancement

    func testGrantedNotificationsCallsOnFinishedAndPersistsNotificationsGrantedTrue() {
        var onFinishedCallCount = 0
        let (defaults, hooks, _) = makeHostedFlow(onFinished: { onFinishedCallCount += 1 })

        // Drive both real steps in sequence, same as a person would experience them.
        hooks.triggerConnectCalendarFinished?(.empty)
        waitUntil { hooks.currentStep == .notifications }

        hooks.triggerNotificationsFinished?(true)

        waitUntil { onFinishedCallCount == 1 }
        XCTAssertEqual(onFinishedCallCount, 1, "FirstRunFlowView's own onFinished() should be called exactly once")
        XCTAssertTrue(defaults.bool(forKey: FirstRunDefaultsKey.notificationsGranted))
    }

    func testDeclinedOrDeniedNotificationsCallsOnFinishedAndPersistsNotificationsGrantedFalse() {
        var onFinishedCallCount = 0
        let (defaults, hooks, _) = makeHostedFlow(onFinished: { onFinishedCallCount += 1 })

        hooks.triggerConnectCalendarFinished?(.empty)
        waitUntil { hooks.currentStep == .notifications }

        hooks.triggerNotificationsFinished?(false)

        waitUntil { onFinishedCallCount == 1 }
        XCTAssertEqual(onFinishedCallCount, 1)
        XCTAssertFalse(defaults.bool(forKey: FirstRunDefaultsKey.notificationsGranted))
    }

    // MARK: - Full sequence

    func testFullSequenceAdvancesBothStepsAndPersistsBothKeysExactlyOnce() {
        var onFinishedCallCount = 0
        let (defaults, hooks, _) = makeHostedFlow(onFinished: { onFinishedCallCount += 1 })

        XCTAssertEqual(hooks.currentStep, .connectCalendar)

        hooks.triggerConnectCalendarFinished?(ConnectedAccountsState(connectedAccountKinds: [.calendar]))
        waitUntil { hooks.currentStep == .notifications }
        XCTAssertEqual(hooks.currentStep, .notifications)
        XCTAssertNotNil(hooks.triggerNotificationsFinished, "Expected the real handleNotificationsFinished method to be captured once the notifications step renders")

        hooks.triggerNotificationsFinished?(true)
        waitUntil { onFinishedCallCount == 1 }

        XCTAssertEqual(onFinishedCallCount, 1)
        XCTAssertTrue(defaults.bool(forKey: FirstRunDefaultsKey.calendarConnected))
        XCTAssertTrue(defaults.bool(forKey: FirstRunDefaultsKey.notificationsGranted))
    }
}
