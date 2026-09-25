import XCTest
import ClearskyCore
@testable import ClearskyApp

/// Exercises `PromisesView.reschedule(_:newDueDate:calendarService:)` — the static,
/// view-independent core of the "Give it a new time" exit — against
/// `MockCalendarService`, with no `PromiseStore`, no real view and no `EKEventStore`
/// involved.
///
/// This is a regression test for the real bug: `giveItANewTime` used to build the
/// rescheduled `Promise` through the initializer without forwarding
/// `calendarEventIdentifier` at all, so it silently defaulted to `nil` — the old hold
/// was left orphaned on the calendar forever, and the rescheduled promise never got a
/// replacement. Every test here asserts on both sides of that: what happened to the
/// *old* hold, and what the *new* `Promise.calendarEventIdentifier` actually is.
final class PromisesViewTests: XCTestCase {
    private func makePromise(
        id: String = "promise-1",
        dueDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        protectedTime: Bool,
        calendarEventIdentifier: String? = nil
    ) -> Promise {
        Promise(
            id: id,
            personName: "Maya Chen",
            whatWasPromised: "Send the invoice",
            dueDate: dueDate,
            protectedTime: protectedTime,
            state: .needsANewPlan,
            calendarEventIdentifier: calendarEventIdentifier
        )
    }

    // MARK: - protectedTime == true, already has a hold (the bug this fixes)

    func testRescheduleOfProtectedPromiseRemovesOldHoldAndAttachesTheNewOne() async throws {
        let mock = MockCalendarService()
        // Seed the mock's in-memory calendar with the "old" hold exactly as
        // `RootView.createCalendarHold(for:)` would have created it originally.
        let oldBlock = ProtectedTimeBlock(
            id: "promise-1",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_001_800),
            ownerTitle: "Send the invoice",
            ownerDetail: "With Maya Chen"
        )
        let oldIdentifier = try await mock.createHold(for: oldBlock)
        let promise = makePromise(protectedTime: true, calendarEventIdentifier: oldIdentifier)
        let newDueDate = Date(timeIntervalSince1970: 1_800_000_000)

        let updated = await PromisesView.reschedule(
            promise,
            newDueDate: newDueDate,
            calendarService: mock
        )

        let result = try XCTUnwrap(updated)

        // The old hold is gone from the calendar...
        XCTAssertNil(mock.holds[oldIdentifier])
        // ...and the promise no longer points to it, or to nil — it points to a
        // brand new hold the mock actually created for the new date.
        let newIdentifier = try XCTUnwrap(result.calendarEventIdentifier)
        XCTAssertNotEqual(newIdentifier, oldIdentifier)
        XCTAssertNotNil(mock.holds[newIdentifier])
        XCTAssertEqual(mock.holds[newIdentifier]?.start, newDueDate)

        // The rest of the reschedule still happened as before.
        XCTAssertEqual(result.dueDate, newDueDate)
        XCTAssertEqual(result.state, .planned)
        XCTAssertEqual(result.id, promise.id)
    }

    // MARK: - protectedTime == false: never touches the calendar, identifier stays nil

    func testRescheduleOfUnprotectedPromiseDoesNotCallCalendarAndStaysNil() async throws {
        let mock = MockCalendarService()
        let promise = makePromise(protectedTime: false, calendarEventIdentifier: nil)
        let newDueDate = Date(timeIntervalSince1970: 1_800_000_000)

        let updated = await PromisesView.reschedule(
            promise,
            newDueDate: newDueDate,
            calendarService: mock
        )

        let result = try XCTUnwrap(updated)

        XCTAssertNil(result.calendarEventIdentifier)
        XCTAssertTrue(mock.holds.isEmpty)
        XCTAssertEqual(mock.requestAccessCallCount, 0)
        XCTAssertEqual(result.dueDate, newDueDate)
        XCTAssertEqual(result.state, .planned)
    }

    // MARK: - protectedTime == true but no existing hold: still creates one, nothing to remove

    func testRescheduleOfProtectedPromiseWithNoExistingHoldStillCreatesANewOne() async throws {
        let mock = MockCalendarService()
        let promise = makePromise(protectedTime: true, calendarEventIdentifier: nil)
        let newDueDate = Date(timeIntervalSince1970: 1_800_000_000)

        let updated = await PromisesView.reschedule(
            promise,
            newDueDate: newDueDate,
            calendarService: mock
        )

        let result = try XCTUnwrap(updated)
        let newIdentifier = try XCTUnwrap(result.calendarEventIdentifier)
        XCTAssertNotNil(mock.holds[newIdentifier])
    }

    // MARK: - Calendar access denied: old identifier is preserved, nothing is called

    func testRescheduleWhenAccessDeniedLeavesOldIdentifierAttachedAndTouchesNothing() async throws {
        let mock = MockCalendarService()
        mock.accessGranted = false
        let oldBlock = ProtectedTimeBlock(
            id: "promise-1",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_001_800),
            ownerTitle: "Send the invoice",
            ownerDetail: "With Maya Chen"
        )
        mock.accessGranted = true
        let oldIdentifier = try await mock.createHold(for: oldBlock)
        mock.accessGranted = false
        let promise = makePromise(protectedTime: true, calendarEventIdentifier: oldIdentifier)

        let updated = await PromisesView.reschedule(
            promise,
            newDueDate: Date(timeIntervalSince1970: 1_800_000_000),
            calendarService: mock
        )

        let result = try XCTUnwrap(updated)

        // Access was never granted, so nothing was removed or created — the old
        // hold is still sitting in the mock's calendar exactly as it was...
        XCTAssertNotNil(mock.holds[oldIdentifier])
        XCTAssertEqual(mock.holds.count, 1)
        // ...and the promise still points to it, rather than losing the reference.
        XCTAssertEqual(result.calendarEventIdentifier, oldIdentifier)
    }
}
