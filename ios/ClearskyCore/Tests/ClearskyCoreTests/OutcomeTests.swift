import XCTest
@testable import ClearskyCore

final class OutcomeTests: XCTestCase {

    func testAllEightNamedOutcomesExist() {
        let expected: Set<Outcome> = [
            .needsAttention,
            .responded,
            .planned,
            .snoozed,
            .waitingOnThem,
            .needsANewPlan,
            .kept,
            .released
        ]
        XCTAssertEqual(Outcome.allCases.count, 8)
        XCTAssertEqual(Set(Outcome.allCases), expected)
    }

    func testAllCasesAreDistinct() {
        XCTAssertEqual(Set(Outcome.allCases).count, Outcome.allCases.count)
    }
}
