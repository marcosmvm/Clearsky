import Foundation
import UserNotifications

/// What it takes to ask the person for OS notification permission.
///
/// This is a protocol — not a call site straight to `UNUserNotificationCenter` — for
/// the same reason `CalendarHolding` wraps `EKEventStore` (see that file's doc
/// comment): `SystemNotificationPermissionService` (the real implementation) needs a
/// live `UNUserNotificationCenter` and shows a real, interactive OS permission alert,
/// none of which a unit test can grant or deny non-interactively in CI or in the
/// simulator. Screens that ask for notification permission —
/// `NotificationsPermissionView` — depend on this protocol instead, so a test can
/// substitute `MockNotificationPermissionService` (in the test target) and assert on
/// call counts and configured outcomes without ever touching a real
/// `UNUserNotificationCenter`.
protocol NotificationPermissionRequesting {
    /// Asks the person for notification permission (alert, sound, badge). Returns
    /// whether access was granted; throws only if the request itself failed (not for
    /// "denied", which is a valid `false` result the caller must handle, not an
    /// error) — same contract as `CalendarHolding.requestAccess()`.
    func requestAccess() async throws -> Bool
}

/// `NotificationPermissionRequesting` backed by a real `UNUserNotificationCenter` —
/// the concrete implementation that actually shows the OS permission prompt.
///
/// Requests `.alert`, `.sound` and `.badge` — what every one of the three V1
/// notification categories `ClearskyCore.NotificationBudget.swift`'s
/// `NotificationCategory` enum names (`morningSummary`, `duePromiseReminder`,
/// `sundayRecap`) needs: a visible alert with a badge count, no more, no less.
/// `.provisional` and `.criticalAlert` are never requested — nothing in V1 is urgent
/// enough to bypass the person's own notification settings or skip the explicit
/// "Allow or decline" choice `01 Product Scope.dc.html` §6 Screen inventory requires
/// for the Notifications screen.
struct SystemNotificationPermissionService: NotificationPermissionRequesting {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAccess() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
}
