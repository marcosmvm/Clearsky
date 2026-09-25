import Foundation
@testable import ClearskyApp

/// An in-memory stand-in for `SystemNotificationPermissionService`, for tests that
/// exercise code which *depends on* `NotificationPermissionRequesting` (screens that
/// ask for notification permission) without a real `UNUserNotificationCenter` or a
/// real, interactive OS permission prompt — neither of which a CI run or a simulator
/// test can provide non-interactively. Same shape as `MockCalendarService`: a `final
/// class` (not a struct) so mutations are visible to the test's own reference after
/// the mock has been handed off to a `NotificationsPermissionViewModel`.
final class MockNotificationPermissionService: NotificationPermissionRequesting {
    /// What `requestAccess()` returns. Defaults to granted so a test opts in to
    /// exercising the denied path explicitly.
    var accessGranted = true
    private(set) var requestAccessCallCount = 0

    func requestAccess() async throws -> Bool {
        requestAccessCallCount += 1
        return accessGranted
    }
}
