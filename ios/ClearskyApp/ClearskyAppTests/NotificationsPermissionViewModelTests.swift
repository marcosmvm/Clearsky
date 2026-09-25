import XCTest
@testable import ClearskyApp

/// Exercises `NotificationsPermissionViewModel` — the testable logic behind
/// `NotificationsPermissionView`'s "Allow notifications" and "Not now" actions — with
/// `MockNotificationPermissionService`, never a real `UNUserNotificationCenter`. See
/// `NotificationsPermissionView.swift`'s type-level doc for why the view's actions
/// live on this separate `ObservableObject` rather than as `@State` + methods on the
/// view struct itself.
@MainActor
final class NotificationsPermissionViewModelTests: XCTestCase {

    // MARK: - Allow

    func testAllowCallsRequestAccessExactlyOnceAndRecordsGranted() async {
        let mock = MockNotificationPermissionService()
        mock.accessGranted = true
        var finishedResults: [Bool] = []
        let viewModel = NotificationsPermissionViewModel(permissionService: mock) { granted in
            finishedResults.append(granted)
        }

        await viewModel.allow()

        XCTAssertEqual(mock.requestAccessCallCount, 1)
        XCTAssertEqual(viewModel.outcome, .granted)
        XCTAssertFalse(viewModel.isRequesting)
        XCTAssertEqual(finishedResults, [true])
    }

    func testAllowRecordsDeniedWhenTheServiceReturnsFalse() async {
        let mock = MockNotificationPermissionService()
        mock.accessGranted = false
        let viewModel = NotificationsPermissionViewModel(permissionService: mock)

        await viewModel.allow()

        XCTAssertEqual(mock.requestAccessCallCount, 1)
        XCTAssertEqual(viewModel.outcome, .denied)
    }

    func testAllowCalledTwiceOnlyAsksTheServiceOnce() async {
        // Guards the "never ask again this session" requirement: a second `allow()`
        // after the first has already resolved must not re-trigger the OS prompt.
        let mock = MockNotificationPermissionService()
        let viewModel = NotificationsPermissionViewModel(permissionService: mock)

        await viewModel.allow()
        await viewModel.allow()

        XCTAssertEqual(mock.requestAccessCallCount, 1)
    }

    // MARK: - Decline

    func testDeclineDoesNotCallRequestAccess() {
        let mock = MockNotificationPermissionService()
        var finishedResults: [Bool] = []
        let viewModel = NotificationsPermissionViewModel(permissionService: mock) { granted in
            finishedResults.append(granted)
        }

        viewModel.decline()

        XCTAssertEqual(mock.requestAccessCallCount, 0)
        XCTAssertEqual(viewModel.outcome, .declined)
        XCTAssertEqual(finishedResults, [false])
    }

    func testDeclineAfterAllowIsANoOp() async {
        let mock = MockNotificationPermissionService()
        let viewModel = NotificationsPermissionViewModel(permissionService: mock)

        await viewModel.allow()
        viewModel.decline()

        XCTAssertEqual(mock.requestAccessCallCount, 1)
        XCTAssertEqual(viewModel.outcome, .granted) // decline() no-ops once already resolved
    }

    func testAllowAfterDeclineIsANoOp() async {
        // Symmetric guard: once the person has declined, a stray `allow()` call must
        // not turn around and ask the OS either.
        let mock = MockNotificationPermissionService()
        let viewModel = NotificationsPermissionViewModel(permissionService: mock)

        viewModel.decline()
        await viewModel.allow()

        XCTAssertEqual(mock.requestAccessCallCount, 0)
        XCTAssertEqual(viewModel.outcome, .declined)
    }
}
