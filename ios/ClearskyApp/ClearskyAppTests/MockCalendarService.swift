import Foundation
import ClearskyCore
@testable import ClearskyApp

/// An in-memory stand-in for `EventKitCalendarService`, for tests that exercise code
/// which *depends on* `CalendarHolding` (screens that create/remove protected-time
/// holds) without a real `EKEventStore`, real calendar permission, or a real calendar
/// — none of which a CI run or a simulator test can provide non-interactively.
///
/// This mock does not, and cannot, prove anything about EventKit itself — there is no
/// real `EKEvent` here to inspect. The one behavior that actually matters (that a
/// real hold never carries the owner's real title/detail) is pure logic lifted into
/// `EventKitCalendarService.resolvedTitleAndDetail(for:)`, which
/// `EventKitCalendarServiceTests` asserts on directly, with no dependency on this
/// mock at all.
final class MockCalendarService: CalendarHolding {
    /// What `requestAccess()` returns. Defaults to granted so a test opts in to
    /// exercising the denied path explicitly.
    var accessGranted = true
    private(set) var requestAccessCallCount = 0

    /// The in-memory calendar: event identifier -> the block it was created for.
    /// Stands in for the calendar EventKit would otherwise write to.
    private(set) var holds: [String: ProtectedTimeBlock] = [:]
    private var nextIdentifier = 0

    enum MockError: Error, Equatable {
        case eventNotFound
    }

    func requestAccess() async throws -> Bool {
        requestAccessCallCount += 1
        return accessGranted
    }

    func createHold(for block: ProtectedTimeBlock) async throws -> String {
        nextIdentifier += 1
        let identifier = "mock-event-\(nextIdentifier)"
        holds[identifier] = block
        return identifier
    }

    func removeHold(eventIdentifier: String) async throws {
        guard holds.removeValue(forKey: eventIdentifier) != nil else {
            throw MockError.eventNotFound
        }
    }
}
