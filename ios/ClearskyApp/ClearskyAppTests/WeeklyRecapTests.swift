import XCTest
import ClearskyCore
@testable import ClearskyApp

/// Exercises `WeeklyRecap.keptPromises(in:referenceDate:)` directly — no
/// `WeeklyRecapView`, no `PromiseStore`, no view rendering — against a fixed
/// `referenceDate` so "this week" is deterministic, same `Date(timeIntervalSince1970:)`
/// fixture convention `PromiseStoreTests` already uses.
final class WeeklyRecapTests: XCTestCase {
    /// Wednesday 2023-11-15 00:00:00 UTC — an arbitrary fixed instant, chosen only so
    /// every test in this file reasons about the same "now".
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ days: Double, from date: Date? = nil) -> Date {
        (date ?? referenceDate).addingTimeInterval(-60 * 60 * 24 * days)
    }

    private func makePromise(
        id: String,
        dueDate: Date,
        state: Outcome
    ) -> Promise {
        Promise(
            id: id,
            personName: "Maya Chen",
            whatWasPromised: "Send the invoice",
            dueDate: dueDate,
            protectedTime: false,
            state: state
        )
    }

    func testKeptPromiseThreeDaysAgoIsIncluded() {
        let promise = makePromise(id: "kept-3-days-ago", dueDate: daysAgo(3), state: .kept)

        let result = WeeklyRecap.keptPromises(in: [promise], referenceDate: referenceDate)

        XCTAssertEqual(result, [promise])
    }

    func testKeptPromiseTenDaysAgoIsExcluded() {
        let promise = makePromise(id: "kept-10-days-ago", dueDate: daysAgo(10), state: .kept)

        let result = WeeklyRecap.keptPromises(in: [promise], referenceDate: referenceDate)

        XCTAssertEqual(result, [])
    }

    func testNonKeptStatesAreExcludedRegardlessOfDate() {
        let nonKeptStates: [Outcome] = [
            .needsAttention, .responded, .planned, .snoozed,
            .waitingOnThem, .needsANewPlan, .released
        ]
        let promises = nonKeptStates.enumerated().map { index, state in
            // Well within the 7-day window on `dueDate` alone, so only `state` can be
            // the reason any of these are excluded.
            makePromise(id: "non-kept-\(index)-\(state.rawValue)", dueDate: daysAgo(1), state: state)
        }

        let result = WeeklyRecap.keptPromises(in: promises, referenceDate: referenceDate)

        XCTAssertEqual(result, [])
    }

    func testWindowBoundaryIsInclusiveAtExactlySevenDaysAgo() {
        let promise = makePromise(id: "kept-exactly-7-days-ago", dueDate: daysAgo(7), state: .kept)

        let result = WeeklyRecap.keptPromises(in: [promise], referenceDate: referenceDate)

        XCTAssertEqual(result, [promise])
    }

    func testJustOutsideTheWindowIsExcluded() {
        // One second earlier than the exact 7-day boundary.
        let promise = makePromise(
            id: "kept-just-outside-window",
            dueDate: daysAgo(7).addingTimeInterval(-1),
            state: .kept
        )

        let result = WeeklyRecap.keptPromises(in: [promise], referenceDate: referenceDate)

        XCTAssertEqual(result, [])
    }

    func testKeptRightNowIsIncluded() {
        let promise = makePromise(id: "kept-right-now", dueDate: referenceDate, state: .kept)

        let result = WeeklyRecap.keptPromises(in: [promise], referenceDate: referenceDate)

        XCTAssertEqual(result, [promise])
    }

    func testMixedListReturnsOnlyTheQualifyingKeptPromisesSortedMostRecentFirst() {
        let keptThreeDaysAgo = makePromise(id: "kept-3", dueDate: daysAgo(3), state: .kept)
        let keptOneDayAgo = makePromise(id: "kept-1", dueDate: daysAgo(1), state: .kept)
        let keptTenDaysAgo = makePromise(id: "kept-10", dueDate: daysAgo(10), state: .kept)
        let plannedYesterday = makePromise(id: "planned-1", dueDate: daysAgo(1), state: .planned)

        let result = WeeklyRecap.keptPromises(
            in: [keptThreeDaysAgo, keptOneDayAgo, keptTenDaysAgo, plannedYesterday],
            referenceDate: referenceDate
        )

        XCTAssertEqual(result, [keptOneDayAgo, keptThreeDaysAgo])
    }

    func testWeeklyRecapInitComputesCountAndKeptPromisesTogether() {
        let keptThreeDaysAgo = makePromise(id: "kept-3", dueDate: daysAgo(3), state: .kept)
        let keptTenDaysAgo = makePromise(id: "kept-10", dueDate: daysAgo(10), state: .kept)

        let recap = WeeklyRecap(promises: [keptThreeDaysAgo, keptTenDaysAgo], referenceDate: referenceDate)

        XCTAssertEqual(recap.count, 1)
        XCTAssertEqual(recap.keptPromises, [keptThreeDaysAgo])
    }

    func testShareTextIsHonestWhenNothingWasKept() {
        let recap = WeeklyRecap(promises: [], referenceDate: referenceDate)

        XCTAssertEqual(recap.shareText, "This week on Clearsky: nothing kept yet.")
    }

    func testShareTextNamesEachMomentWhenSomethingWasKept() {
        let promise = makePromise(id: "kept-3", dueDate: daysAgo(3), state: .kept)

        let recap = WeeklyRecap(promises: [promise], referenceDate: referenceDate)

        XCTAssertTrue(recap.shareText.contains("Maya Chen"))
        XCTAssertTrue(recap.shareText.contains("Send the invoice"))
        XCTAssertTrue(recap.shareText.contains("once"))
    }
}
