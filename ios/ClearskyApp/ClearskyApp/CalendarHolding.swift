import Foundation
import ClearskyCore

/// What it takes to turn a `ProtectedTimeBlock` into (and back out of) a real hold on
/// a person's device calendar.
///
/// This is a protocol — not a call site straight to `EKEventStore` — for one reason:
/// `EventKitCalendarService` (the real implementation) needs a live `EKEventStore`,
/// calendar permission and an actual calendar to write to, none of which a unit test
/// can grant non-interactively in CI or in the simulator. Testing the one behavior
/// that matters here (see `EventKitCalendarService.resolvedTitleAndDetail(for:)`)
/// does not require any of that, but code that *calls* a calendar service — screens
/// that create or remove protected-time holds — still needs something to depend on.
/// `MockCalendarService` in the test target is the other conformer.
protocol CalendarHolding {
    /// Asks the person for calendar permission. Returns whether access was granted;
    /// throws only if the request itself failed (not for "denied", which is a valid
    /// `false` result the caller must handle, not an error).
    func requestAccess() async throws -> Bool

    /// Creates a calendar hold for `block` and returns the created event's
    /// identifier, which the caller stores alongside the `ProtectedTimeBlock` so a
    /// later `removeHold(eventIdentifier:)` can find it again.
    func createHold(for block: ProtectedTimeBlock) async throws -> String

    /// Removes the calendar hold previously created with the identifier
    /// `createHold(for:)` returned.
    func removeHold(eventIdentifier: String) async throws
}
