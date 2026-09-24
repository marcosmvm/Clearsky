import XCTest
@testable import ClearskyCore

final class TriageStateMachineTests: XCTestCase {

    // MARK: - Every row of the canonical table is accepted

    func testEveryCanonicalRowIsAccepted() {
        let expectedRows: [(from: Outcome, action: TriageAction, to: Outcome)] = [
            (.needsAttention, .sendReply, .responded),
            (.needsAttention, .confirmPlan, .planned),
            (.needsAttention, .chooseRevisitTime, .snoozed),
            (.needsAttention, .markAwaitingReply, .waitingOnThem),
            (.responded, .markAwaitingReply, .waitingOnThem),
            (.needsAttention, .letGo, .released),
            (.planned, .letGo, .released),
            (.needsANewPlan, .letGo, .released),
            (.planned, .completeCommitment, .kept),
            (.planned, .dateNoLongerWorks, .needsANewPlan),
            (.snoozed, .returnDateArrives, .needsAttention),
            (.needsANewPlan, .reschedulePlan, .planned)
        ]

        // The table should contain exactly these rows, no more, no fewer.
        XCTAssertEqual(TriageStateMachine.table.count, expectedRows.count)

        for row in expectedRows {
            XCTAssertEqual(
                TriageStateMachine.canTransition(from: row.from, via: row.action),
                row.to,
                "\(row.from) --\(row.action)--> \(row.to) should be a legal transition"
            )
            XCTAssertNoThrow(
                try TriageStateMachine.transition(from: row.from, via: row.action),
                "\(row.from) --\(row.action)--> \(row.to) should not throw"
            )
        }
    }

    // MARK: - Unlisted transitions are rejected

    func testNeedsAttentionCannotJumpDirectlyToKept() {
        XCTAssertNil(TriageStateMachine.canTransition(from: .needsAttention, via: .completeCommitment))
    }

    func testWaitingOnThemCannotBeCompletedDirectlyToKept() {
        // "Waiting on them" has no completion path at all (see below), so no action
        // — completion or otherwise — should move it to Kept.
        for action in TriageAction.allCases {
            XCTAssertNil(
                TriageStateMachine.canTransition(from: .waitingOnThem, via: action),
                "Waiting on them should have no outgoing transitions via \(action)"
            )
        }
    }

    func testSnoozedCannotBeReleasedDirectly() {
        // Snoozed --let go--> Released is not a row in the canonical table.
        XCTAssertNil(TriageStateMachine.canTransition(from: .snoozed, via: .letGo))
    }

    func testIllegalTransitionThrows() {
        XCTAssertThrowsError(
            try TriageStateMachine.transition(from: .needsAttention, via: .completeCommitment)
        ) { error in
            XCTAssertEqual(
                error as? TriageStateMachine.TransitionError,
                .illegalTransition(from: .needsAttention, action: .completeCommitment)
            )
        }
    }

    // MARK: - Waiting on them has no completion/checkbox-style action leading to it

    func testWaitingOnThemIsOnlyReachableByMarkAwaitingReply() {
        let rulesLeadingToWaiting = TriageStateMachine.table.filter { $0.to == .waitingOnThem }
        XCTAssertFalse(rulesLeadingToWaiting.isEmpty, "Waiting on them should be reachable at all")
        for rule in rulesLeadingToWaiting {
            XCTAssertEqual(rule.action, .markAwaitingReply)
            XCTAssertNotEqual(
                rule.action,
                .completeCommitment,
                "Waiting on them must not be reachable via a completion-style action"
            )
        }
    }

    // MARK: - Every rule's `from` state can legally reach it only via the table

    func testTableHasNoDuplicateFromActionPairs() {
        var seen = Set<String>()
        for rule in TriageStateMachine.table {
            let key = "\(rule.from.rawValue)/\(rule.action.rawValue)"
            XCTAssertTrue(seen.insert(key).inserted, "Duplicate rule for \(key)")
        }
    }

    // MARK: - Needs a new plan -> Planned via .reschedulePlan (Promise Detail's
    // "give it a new time" exit; see PromiseNeedsANewPlanExit.giveItANewTime and
    // TriagePresentation.triageAction(for:from:)'s doc comment)

    func testNeedsANewPlanCanRescheduleToPlanned() {
        XCTAssertEqual(
            TriageStateMachine.canTransition(from: .needsANewPlan, via: .reschedulePlan),
            .planned
        )
        XCTAssertNoThrow(
            try TriageStateMachine.transition(from: .needsANewPlan, via: .reschedulePlan)
        )
    }

    func testReschedulePlanRowCarriesExpectedMetadata() {
        let rule = TriageStateMachine.rule(for: .needsANewPlan, via: .reschedulePlan)
        XCTAssertEqual(rule?.requiredMetadata, "prior date, prior person/thread, new date/time")
    }

    func testReschedulePlanIsIllegalFromEveryOtherState() {
        for state in Outcome.allCases where state != .needsANewPlan {
            XCTAssertNil(
                TriageStateMachine.canTransition(from: state, via: .reschedulePlan),
                "reschedulePlan should only be legal from .needsANewPlan, not from \(state)"
            )
        }
    }

    func testNeedsANewPlanStillLetsGoUnchanged() {
        // The pre-existing transition must keep working exactly as before: adding
        // .reschedulePlan must not touch or replace the .letGo row.
        XCTAssertEqual(
            TriageStateMachine.canTransition(from: .needsANewPlan, via: .letGo),
            .released
        )
    }

    func testReschedulePlanIsTheOnlyNewLegalPairAddedForNeedsANewPlan() {
        // .needsANewPlan should now have exactly two outgoing rows: the pre-existing
        // .letGo -> .released, and the new .reschedulePlan -> .planned. No other
        // action should be legal from .needsANewPlan.
        let outgoing = TriageStateMachine.table.filter { $0.from == .needsANewPlan }
        let actions = Set(outgoing.map { $0.action })
        XCTAssertEqual(actions, [.letGo, .reschedulePlan])
    }
}
