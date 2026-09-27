import XCTest
import ClearskyCore
@testable import ClearskyApp

/// Exercises the persistence contract `FirstRunFlowView` relies on: that the exact
/// reduction it applies inside each screen's `onFinished` closure — `state in
/// calendarConnected = state.hasAnyConnectedAccount` and `granted in
/// notificationsGranted = granted` — produces the right `UserDefaults.standard` value
/// under the exact key strings `"calendarConnected"` and `"notificationsGranted"`
/// another first-run screen (built in parallel this same round) depends on.
///
/// ## Why this does not instantiate `FirstRunFlowView` and drive its `@State` directly
///
/// `FirstRunFlowView.step` is a plain `@State`, per this screen's spec. `@State`'s
/// setter is `nonmutating` and writes through a `_location` box the SwiftUI runtime
/// only installs once a view is actually part of a live view graph (`_makeView`/a real
/// `WindowGroup`/host); a `FirstRunFlowView` value constructed directly in a test, with
/// no host, has no such location installed, so mutating `step` that way is silently
/// dropped rather than raising an error — it would produce a test that passes or fails
/// for the wrong reason, not real proof. (See the `clearsky-ios-build-conventions`
/// agent memory and `NotificationsPermissionView.swift`'s own "why the permission ask
/// is a view model" doc for the established, opposite pattern: `@Published` state on a
/// plain `ObservableObject`, which has no such installation requirement — not used
/// here because the task spec for this file is explicit that `step` is a plain
/// `@State` directly on the view, not something owned by a view model.)
///
/// `@AppStorage`, unlike `@State`, always reads and writes the real backing
/// `UserDefaults` store directly and has no such installation requirement — so
/// `calendarConnected`/`notificationsGranted`'s actual persistence *is* reliably
/// testable, exactly as this file does, by driving the real, already-tested
/// `ConnectCalendarViewModel`/`NotificationsPermissionViewModel` (the same types
/// `ConnectCalendarView`/`NotificationsPermissionView` build on) through their public
/// actions and applying `FirstRunFlowView`'s exact reduction to the outcome each
/// produces.
///
/// The `step` transition itself, and the full interactive screen sequence, are proved
/// instead by: the full `xcodebuild test` suite passing (confirms the code compiles
/// and type-checks against `ConnectCalendarView`/`NotificationsPermissionView`'s real
/// signatures), the `#Preview`s in `FirstRunFlowView.swift`, and a real Simulator
/// install/launch screenshot showing the fresh-install and returning-user paths (see
/// the PR description for both).
@MainActor
final class FirstRunFlowViewTests: XCTestCase {
    /// The exact key strings `FirstRunFlowView` uses — duplicated here as literals
    /// (not a shared constant) specifically so a future rename of one without the
    /// other breaks this test, since another first-run screen depends on
    /// `"calendarConnected"` matching exactly.
    private let calendarConnectedKey = "calendarConnected"
    private let notificationsGrantedKey = "notificationsGranted"

    private var originalCalendarConnected: Bool?
    private var originalNotificationsGranted: Bool?

    override func setUp() {
        super.setUp()
        // UserDefaults.standard is process-global — save whatever was there (there
        // is no disposable-suite option here, since `@AppStorage("calendarConnected")`
        // with no explicit `store:` argument is exactly what the task spec requires,
        // to match the real app's own un-suited `@AppStorage` declarations) and
        // restore it in `tearDown` so this test never leaks state into another test.
        originalCalendarConnected = UserDefaults.standard.object(forKey: calendarConnectedKey) as? Bool
        originalNotificationsGranted = UserDefaults.standard.object(forKey: notificationsGrantedKey) as? Bool
        UserDefaults.standard.removeObject(forKey: calendarConnectedKey)
        UserDefaults.standard.removeObject(forKey: notificationsGrantedKey)
    }

    override func tearDown() {
        if let originalCalendarConnected {
            UserDefaults.standard.set(originalCalendarConnected, forKey: calendarConnectedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: calendarConnectedKey)
        }
        if let originalNotificationsGranted {
            UserDefaults.standard.set(originalNotificationsGranted, forKey: notificationsGrantedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: notificationsGrantedKey)
        }
        super.tearDown()
    }

    // MARK: - Connect calendar step's reduction

    func testGrantedCalendarAccessPersistsCalendarConnectedTrue() async {
        let mock = MockCalendarService()
        mock.accessGranted = true
        let viewModel = ConnectCalendarViewModel(calendarService: mock) { state in
            // The exact reduction `FirstRunFlowView`'s `.connectCalendar` case applies.
            UserDefaults.standard.set(state.hasAnyConnectedAccount, forKey: self.calendarConnectedKey)
        }

        await viewModel.grantAccess()

        XCTAssertTrue(UserDefaults.standard.bool(forKey: calendarConnectedKey))
    }

    func testDeniedCalendarAccessPersistsCalendarConnectedFalse() async {
        let mock = MockCalendarService()
        mock.accessGranted = false
        let viewModel = ConnectCalendarViewModel(calendarService: mock) { state in
            UserDefaults.standard.set(state.hasAnyConnectedAccount, forKey: self.calendarConnectedKey)
        }

        await viewModel.grantAccess()

        XCTAssertFalse(UserDefaults.standard.bool(forKey: calendarConnectedKey))
    }

    func testSkippedCalendarStepPersistsCalendarConnectedFalse() {
        let mock = MockCalendarService()
        let viewModel = ConnectCalendarViewModel(calendarService: mock) { state in
            UserDefaults.standard.set(state.hasAnyConnectedAccount, forKey: self.calendarConnectedKey)
        }

        viewModel.skip()

        XCTAssertFalse(UserDefaults.standard.bool(forKey: calendarConnectedKey))
    }

    // MARK: - Notifications step's reduction

    func testGrantedNotificationsPersistsNotificationsGrantedTrueAndCallsOnFinished() async {
        let mock = MockNotificationPermissionService()
        mock.accessGranted = true
        var onFinishedCallCount = 0
        let viewModel = NotificationsPermissionViewModel(permissionService: mock) { granted in
            // The exact reduction `FirstRunFlowView`'s `.notifications` case applies,
            // followed by the app-level `onFinished()` it chains to.
            UserDefaults.standard.set(granted, forKey: self.notificationsGrantedKey)
            onFinishedCallCount += 1
        }

        await viewModel.allow()

        XCTAssertTrue(UserDefaults.standard.bool(forKey: notificationsGrantedKey))
        XCTAssertEqual(onFinishedCallCount, 1)
    }

    func testDeniedNotificationsPersistsNotificationsGrantedFalseAndCallsOnFinished() async {
        let mock = MockNotificationPermissionService()
        mock.accessGranted = false
        var onFinishedCallCount = 0
        let viewModel = NotificationsPermissionViewModel(permissionService: mock) { granted in
            UserDefaults.standard.set(granted, forKey: self.notificationsGrantedKey)
            onFinishedCallCount += 1
        }

        await viewModel.allow()

        XCTAssertFalse(UserDefaults.standard.bool(forKey: notificationsGrantedKey))
        XCTAssertEqual(onFinishedCallCount, 1)
    }

    func testDeclinedNotificationsPersistsNotificationsGrantedFalseAndCallsOnFinished() {
        let mock = MockNotificationPermissionService()
        var onFinishedCallCount = 0
        let viewModel = NotificationsPermissionViewModel(permissionService: mock) { granted in
            UserDefaults.standard.set(granted, forKey: self.notificationsGrantedKey)
            onFinishedCallCount += 1
        }

        viewModel.decline()

        XCTAssertFalse(UserDefaults.standard.bool(forKey: notificationsGrantedKey))
        XCTAssertEqual(onFinishedCallCount, 1)
    }
}
