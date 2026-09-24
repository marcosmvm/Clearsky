import XCTest
@testable import ClearskyCore

final class PromiseOwnershipTests: XCTestCase {

    // MARK: - PromiseOwnershipGroup has exactly the four groups the audit doc names

    func testGroupCasesMatchSpec() {
        let expected: Set<PromiseOwnershipGroup> = [.yoursToKeep, .notYourMove, .kept, .released]
        XCTAssertEqual(PromiseOwnershipGroup.allCases.count, 4)
        XCTAssertEqual(Set(PromiseOwnershipGroup.allCases), expected)
    }

    func testGroupDisplayTitlesMatchAuditDocWording() {
        XCTAssertEqual(PromiseOwnershipGroup.yoursToKeep.displayTitle, "Yours to keep")
        XCTAssertEqual(PromiseOwnershipGroup.notYourMove.displayTitle, "Not your move")
        XCTAssertEqual(PromiseOwnershipGroup.kept.displayTitle, "Kept")
        XCTAssertEqual(PromiseOwnershipGroup.released.displayTitle, "Released")
    }

    // MARK: - Every Outcome maps to the intended group (or intentionally to nil)

    func testEveryOutcomeMapsToIntendedGroup() {
        let expected: [Outcome: PromiseOwnershipGroup?] = [
            .needsAttention: nil,
            .responded: nil,
            .planned: .yoursToKeep,
            .snoozed: nil,
            .waitingOnThem: .notYourMove,
            .needsANewPlan: .yoursToKeep,
            .kept: .kept,
            .released: .released
        ]

        // Exercise every case in `Outcome`, not just the ones listed above, so a
        // future new case can't silently fall through untested.
        XCTAssertEqual(Set(expected.keys), Set(Outcome.allCases))

        for outcome in Outcome.allCases {
            XCTAssertEqual(
                PromiseOwnership.group(for: outcome),
                expected[outcome] ?? nil,
                "\(outcome) mapped to an unexpected group"
            )
        }
    }

    func testTriageOnlyStatesAreExcludedFromThePromisesList() {
        XCTAssertNil(PromiseOwnership.group(for: .needsAttention))
        XCTAssertNil(PromiseOwnership.group(for: .responded))
        XCTAssertNil(PromiseOwnership.group(for: .snoozed))
    }

    func testWaitingOnThemGroupsUnderNotYourMove() {
        XCTAssertEqual(PromiseOwnership.group(for: .waitingOnThem), .notYourMove)
    }

    func testPlannedAndNeedsANewPlanBothGroupUnderYoursToKeep() {
        // Both are still owned by the user and still actionable — neither should
        // disappear from the Promises list, and the audit doc defines no fifth group.
        XCTAssertEqual(PromiseOwnership.group(for: .planned), .yoursToKeep)
        XCTAssertEqual(PromiseOwnership.group(for: .needsANewPlan), .yoursToKeep)
    }

    func testNeedsANewPlanNeverDisappearsFromTheList() {
        XCTAssertNotNil(PromiseOwnership.group(for: .needsANewPlan))
    }

    // MARK: - Checkbox/tap-to-complete invariant

    func testWaitingOnThemIsNeverDirectlyCompletable() {
        XCTAssertFalse(PromiseOwnership.isDirectlyCompletable(.waitingOnThem))
    }

    func testOnlyPlannedIsDirectlyCompletable() {
        let expected: [Outcome: Bool] = [
            .needsAttention: false,
            .responded: false,
            .planned: true,
            .snoozed: false,
            .waitingOnThem: false,
            .needsANewPlan: false,
            .kept: false,
            .released: false
        ]

        XCTAssertEqual(Set(expected.keys), Set(Outcome.allCases))

        for outcome in Outcome.allCases {
            XCTAssertEqual(
                PromiseOwnership.isDirectlyCompletable(outcome),
                expected[outcome],
                "\(outcome) had an unexpected direct-completability result"
            )
        }
    }

    func testIsDirectlyCompletableAgreesWithTheCanonicalStateMachine() {
        // Bake-in check: this function must never drift from the one canonical
        // source of truth for legal transitions.
        for outcome in Outcome.allCases {
            let expected = TriageStateMachine.canTransition(from: outcome, via: .completeCommitment) != nil
            XCTAssertEqual(PromiseOwnership.isDirectlyCompletable(outcome), expected)
        }
    }

    // MARK: - PromiseNeedsANewPlanExit is a closed set of exactly three named exits

    func testExitHasExactlyThreeCases() {
        XCTAssertEqual(PromiseNeedsANewPlanExit.allCases.count, 3)
    }

    func testExitCasesMatchSpec() {
        let expected: Set<PromiseNeedsANewPlanExit> = [.keepIt, .giveItANewTime, .letItGo]
        XCTAssertEqual(Set(PromiseNeedsANewPlanExit.allCases), expected)
    }

    func testExitDisplayLabelsMatchAuditDocWording() {
        XCTAssertEqual(PromiseNeedsANewPlanExit.keepIt.displayLabel, "Keep it")
        XCTAssertEqual(PromiseNeedsANewPlanExit.giveItANewTime.displayLabel, "Give it a new time")
        XCTAssertEqual(PromiseNeedsANewPlanExit.letItGo.displayLabel, "Let it go")
    }

    func testLetItGoMatchesTheOneLegalTransitionOutOfNeedsANewPlan() {
        // `.letGo` is the only legal action out of `.needsANewPlan` in the canonical
        // table (needsANewPlan -> released). The other two exits are UI-facing only
        // and intentionally do not correspond to a table row — see the doc comment
        // on `PromiseNeedsANewPlanExit`.
        XCTAssertEqual(
            TriageStateMachine.canTransition(from: .needsANewPlan, via: .letGo),
            .released
        )
    }
}
