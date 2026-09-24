import XCTest
import ClearskyCore
@testable import ClearskyApp

/// Tests the one behavior of `EventKitCalendarService` that actually matters: a real
/// calendar hold never carries the block's real `ownerTitle`/`ownerDetail`, no matter
/// what they are. This is asserted purely, through
/// `EventKitCalendarService.resolvedTitleAndDetail(for:)`, so it runs in CI and in
/// the simulator with no real `EKEventStore`, no calendar permission, and no
/// interactive prompt — none of which a test process can provide.
///
/// `createHold(for:)`/`removeHold(eventIdentifier:)` themselves call into a real
/// `EKEventStore` and are intentionally not exercised here; `MockCalendarService`
/// (also in this target) is what code that merely *depends on* `CalendarHolding`
/// should test against.
final class EventKitCalendarServiceTests: XCTestCase {

    // MARK: - resolvedTitleAndDetail always writes "Busy" with no detail

    func testResolvedTitleAndDetailIsAlwaysBusyWithNoDetail() {
        let block = ProtectedTimeBlock(
            id: "block-1",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_007_200),
            ownerTitle: "Dinner with Jamie",
            ownerDetail: "At Nido — don't schedule over this"
        )

        let resolved = EventKitCalendarService.resolvedTitleAndDetail(for: block)

        XCTAssertEqual(resolved.title, "Busy")
        XCTAssertNil(resolved.detail)
    }

    func testResolvedTitleAndDetailMatchesProtectedTimePresentationForOtherViewer() {
        // resolvedTitleAndDetail must exactly mirror what ClearskyCore's own
        // "other viewer" resolver produces — this service does not invent its own
        // busy label.
        let block = ProtectedTimeBlock(
            id: "block-2",
            start: Date(),
            end: Date().addingTimeInterval(3_600),
            ownerTitle: "Therapy",
            ownerDetail: "Dr. Alvarez, downtown"
        )
        let expected = ProtectedTimePresentation.resolve(block, for: .otherViewer)

        let resolved = EventKitCalendarService.resolvedTitleAndDetail(for: block)

        XCTAssertEqual(resolved.title, expected.title)
        XCTAssertEqual(resolved.detail, expected.detail)
    }

    func testResolvedTitleAndDetailNeverLeaksOwnerTitleOrDetailRegardlessOfBlockContent() {
        // Vary the owner-authored content across several blocks, including one where
        // the owner title happens to contain the word "Busy" — the resolved value
        // must still always be exactly ("Busy", nil), never a function of the real
        // content.
        let blocks = [
            ProtectedTimeBlock(
                id: "a", start: Date(), end: Date().addingTimeInterval(3_600),
                ownerTitle: "Protected evening", ownerDetail: "Nothing can land here"
            ),
            ProtectedTimeBlock(
                id: "b", start: Date(), end: Date().addingTimeInterval(3_600),
                ownerTitle: "Deep work", ownerDetail: "Notifications paused"
            ),
            ProtectedTimeBlock(
                id: "c", start: Date(), end: Date().addingTimeInterval(3_600),
                ownerTitle: "Not Busy, actually free", ownerDetail: "Busy is a lie"
            ),
            ProtectedTimeBlock(
                id: "d", start: Date(), end: Date().addingTimeInterval(3_600),
                ownerTitle: "", ownerDetail: ""
            )
        ]

        for block in blocks {
            let resolved = EventKitCalendarService.resolvedTitleAndDetail(for: block)
            XCTAssertEqual(resolved.title, "Busy")
            XCTAssertNil(resolved.detail)
            XCTAssertNotEqual(resolved.title, block.ownerTitle)
        }
    }

    // MARK: - MockCalendarService (sanity: the in-memory stand-in behaves like the protocol contract)

    func testMockCreateHoldThenRemoveHoldRoundTrips() async throws {
        let mock = MockCalendarService()
        let block = ProtectedTimeBlock(
            id: "block-3",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_007_200),
            ownerTitle: "Protected evening",
            ownerDetail: "Nothing can land here"
        )

        let identifier = try await mock.createHold(for: block)
        XCTAssertEqual(mock.holds[identifier], block)

        try await mock.removeHold(eventIdentifier: identifier)
        XCTAssertNil(mock.holds[identifier])
    }

    func testMockRemoveHoldThrowsForAnUnknownIdentifier() async {
        let mock = MockCalendarService()

        await XCTAssertThrowsErrorAsync(try await mock.removeHold(eventIdentifier: "does-not-exist")) { error in
            XCTAssertEqual(error as? MockCalendarService.MockError, .eventNotFound)
        }
    }

    func testMockRequestAccessReflectsConfiguredGrantState() async throws {
        let mock = MockCalendarService()
        mock.accessGranted = false

        let granted = try await mock.requestAccess()

        XCTAssertFalse(granted)
        XCTAssertEqual(mock.requestAccessCallCount, 1)
    }
}

/// XCTAssertThrowsError has no async overload in XCTest yet; this is the standard
/// small shim for awaiting a throwing async expression in an assertion.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
