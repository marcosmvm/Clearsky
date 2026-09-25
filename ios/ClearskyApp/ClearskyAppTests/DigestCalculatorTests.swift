import XCTest
import ClearskyCore
@testable import ClearskyApp

/// Exercises `DigestCalculator` — the view-independent counting/selection logic behind
/// `DigestView` — against small, fixed sets of promises. No view, no `PromiseStore`,
/// no SwiftUI involved, same "test the pure logic directly" pattern
/// `PromisesViewTests.swift` uses for `PromisesView.reschedule`.
final class DigestCalculatorTests: XCTestCase {
    private func makePromise(
        id: String,
        personName: String = "Test Person",
        whatWasPromised: String = "Do a thing",
        dueDate: Date,
        state: Outcome
    ) -> Promise {
        Promise(
            id: id,
            personName: personName,
            whatWasPromised: whatWasPromised,
            dueDate: dueDate,
            protectedTime: false,
            state: state
        )
    }

    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Kept / let-go counts

    func testSummaryCountsKeptAndReleasedAcrossAMixOfStates() {
        let promises = [
            makePromise(id: "kept-1", dueDate: referenceDate.addingTimeInterval(-1_000), state: .kept),
            makePromise(id: "kept-2", dueDate: referenceDate.addingTimeInterval(-2_000), state: .kept),
            makePromise(id: "released-1", dueDate: referenceDate.addingTimeInterval(-3_000), state: .released),
            makePromise(id: "planned-1", dueDate: referenceDate.addingTimeInterval(1_000), state: .planned),
            makePromise(id: "waiting-1", dueDate: referenceDate.addingTimeInterval(1_000), state: .waitingOnThem),
            makePromise(id: "needs-a-new-plan-1", dueDate: referenceDate.addingTimeInterval(-500), state: .needsANewPlan)
        ]

        let summary = DigestCalculator.summary(for: promises, referenceDate: referenceDate)

        XCTAssertEqual(summary.keptCount, 2)
        XCTAssertEqual(summary.releasedCount, 1)
        XCTAssertEqual(Set(summary.keptPromises.map(\.id)), ["kept-1", "kept-2"])
        XCTAssertEqual(summary.releasedPromises.map(\.id), ["released-1"])
    }

    func testSummaryCountsAreZeroWhenNoPromiseIsKeptOrReleased() {
        let promises = [
            makePromise(id: "planned-1", dueDate: referenceDate.addingTimeInterval(1_000), state: .planned)
        ]

        let summary = DigestCalculator.summary(for: promises, referenceDate: referenceDate)

        XCTAssertEqual(summary.keptCount, 0)
        XCTAssertEqual(summary.releasedCount, 0)
        XCTAssertTrue(summary.keptPromises.isEmpty)
        XCTAssertTrue(summary.releasedPromises.isEmpty)
    }

    // MARK: - "One thing to watch" selection

    /// Selection rule under test: **oldest-unresolved** — the `.needsANewPlan`
    /// promise with the *earliest* `dueDate` wins, not the one due soonest.
    func testOneThingToWatchPicksTheEarliestDueDateAmongMultipleCandidates() {
        let promises = [
            makePromise(
                id: "needs-a-new-plan-recent",
                personName: "James Okafor",
                dueDate: referenceDate.addingTimeInterval(-1 * 60 * 60 * 24),
                state: .needsANewPlan
            ),
            makePromise(
                id: "needs-a-new-plan-oldest",
                personName: "Priya Patel",
                dueDate: referenceDate.addingTimeInterval(-10 * 60 * 60 * 24),
                state: .needsANewPlan
            ),
            makePromise(
                id: "needs-a-new-plan-middle",
                personName: "Sam Rivera",
                dueDate: referenceDate.addingTimeInterval(-5 * 60 * 60 * 24),
                state: .needsANewPlan
            ),
            // Not a candidate: wrong state entirely.
            makePromise(id: "kept-1", dueDate: referenceDate.addingTimeInterval(-20 * 60 * 60 * 24), state: .kept)
        ]

        let watch = DigestCalculator.oneThingToWatch(in: promises, referenceDate: referenceDate)

        let result = try! XCTUnwrap(watch)
        XCTAssertEqual(result.promise.id, "needs-a-new-plan-oldest")
        XCTAssertEqual(result.promise.personName, "Priya Patel")
        XCTAssertEqual(result.daysSinceDue, 10)
    }

    func testOneThingToWatchBreaksTiedDueDatesById() {
        let tiedDueDate = referenceDate.addingTimeInterval(-3 * 60 * 60 * 24)
        let promises = [
            makePromise(id: "zzz-later-id", dueDate: tiedDueDate, state: .needsANewPlan),
            makePromise(id: "aaa-earlier-id", dueDate: tiedDueDate, state: .needsANewPlan)
        ]

        let watch = DigestCalculator.oneThingToWatch(in: promises, referenceDate: referenceDate)

        XCTAssertEqual(watch?.promise.id, "aaa-earlier-id")
    }

    func testOneThingToWatchIsNilWhenThereIsNoNeedsANewPlanPromise() {
        let promises = [
            makePromise(id: "kept-1", dueDate: referenceDate.addingTimeInterval(-1_000), state: .kept),
            makePromise(id: "released-1", dueDate: referenceDate.addingTimeInterval(-2_000), state: .released),
            makePromise(id: "planned-1", dueDate: referenceDate.addingTimeInterval(1_000), state: .planned),
            makePromise(id: "waiting-1", dueDate: referenceDate.addingTimeInterval(1_000), state: .waitingOnThem)
        ]

        let watch = DigestCalculator.oneThingToWatch(in: promises, referenceDate: referenceDate)

        XCTAssertNil(watch)
    }

    func testOneThingToWatchIsNilForAnEmptyPromiseList() {
        let watch = DigestCalculator.oneThingToWatch(in: [], referenceDate: referenceDate)
        XCTAssertNil(watch)
    }

    // MARK: - Summary.isEmpty

    func testSummaryIsEmptyOnlyWhenThereIsNothingToReport() {
        let empty = DigestCalculator.summary(for: [], referenceDate: referenceDate)
        XCTAssertTrue(empty.isEmpty)

        let withOnlyAPlannedPromise = DigestCalculator.summary(
            for: [makePromise(id: "planned-1", dueDate: referenceDate.addingTimeInterval(1_000), state: .planned)],
            referenceDate: referenceDate
        )
        XCTAssertTrue(withOnlyAPlannedPromise.isEmpty)

        let withOneKept = DigestCalculator.summary(
            for: [makePromise(id: "kept-1", dueDate: referenceDate.addingTimeInterval(-1_000), state: .kept)],
            referenceDate: referenceDate
        )
        XCTAssertFalse(withOneKept.isEmpty)

        let withOnlyOneThingToWatch = DigestCalculator.summary(
            for: [makePromise(id: "needs-a-new-plan-1", dueDate: referenceDate.addingTimeInterval(-1_000), state: .needsANewPlan)],
            referenceDate: referenceDate
        )
        XCTAssertFalse(withOnlyOneThingToWatch.isEmpty)
    }
}
