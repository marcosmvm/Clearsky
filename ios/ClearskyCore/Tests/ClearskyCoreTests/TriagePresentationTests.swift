import XCTest
@testable import ClearskyCore

final class TriagePresentationTests: XCTestCase {

    // MARK: - Helpers

    private func explanation(
        recommendedAction: TriageExplanation.RecommendedAction,
        alternativeActions: [TriageExplanation.RecommendedAction]
    ) -> TriageExplanation {
        TriageExplanation(
            whyNow: "test fixture",
            signals: [],
            ifNoAction: "test fixture",
            nextReviewAt: nil,
            recommendedAction: recommendedAction,
            alternativeActions: alternativeActions
        )
    }

    // MARK: - Round trip: .needsAttention (every RecommendedAction is legal from here)

    func testNeedsAttentionRoundTripsEveryRecommendedAction() {
        let explanation = explanation(
            recommendedAction: .respond,
            alternativeActions: [.plan, .snooze, .wait, .letGo]
        )

        let presentation = TriagePresentation.build(state: .needsAttention, explanation: explanation)

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(
            presentation.recommended,
            TriageResolvedAction(source: .respond, triageAction: .sendReply, resultingState: .responded)
        )
        XCTAssertEqual(
            Set(presentation.alternatives),
            Set([
                TriageResolvedAction(source: .plan, triageAction: .confirmPlan, resultingState: .planned),
                TriageResolvedAction(source: .snooze, triageAction: .chooseRevisitTime, resultingState: .snoozed),
                TriageResolvedAction(source: .wait, triageAction: .markAwaitingReply, resultingState: .waitingOnThem),
                TriageResolvedAction(source: .letGo, triageAction: .letGo, resultingState: .released)
            ])
        )
        XCTAssertEqual(presentation.alternatives.count, 4, "None of the four alternatives should be dropped from .needsAttention")
    }

    // MARK: - Round trip: .responded (only .wait / markAwaitingReply is legal)

    func testRespondedRoundTripsOnlyWait() {
        let explanation = explanation(
            recommendedAction: .wait,
            alternativeActions: [.respond, .plan, .snooze, .letGo]
        )

        let presentation = TriagePresentation.build(state: .responded, explanation: explanation)

        XCTAssertEqual(
            presentation.recommended,
            TriageResolvedAction(source: .wait, triageAction: .markAwaitingReply, resultingState: .waitingOnThem)
        )
        XCTAssertTrue(
            presentation.alternatives.isEmpty,
            "Respond/plan/snooze/letGo have no legal transition from .responded and must be dropped, not crash"
        )
    }

    // MARK: - Round trip: .planned (only .letGo is legal)

    func testPlannedRoundTripsOnlyLetGo() {
        let explanation = explanation(
            recommendedAction: .letGo,
            alternativeActions: [.respond, .plan, .snooze, .wait]
        )

        let presentation = TriagePresentation.build(state: .planned, explanation: explanation)

        XCTAssertEqual(
            presentation.recommended,
            TriageResolvedAction(source: .letGo, triageAction: .letGo, resultingState: .released)
        )
        XCTAssertTrue(
            presentation.alternatives.isEmpty,
            "Respond/plan/snooze/wait have no legal transition from .planned and must be dropped, not crash"
        )
    }

    // MARK: - Round trip: .snoozed (only returnDateArrives is legal, and no RecommendedAction maps to it)

    func testSnoozedHasNoLegalRecommendedActionButDoesNotCrash() {
        // .snoozed has exactly one legal outgoing transition in the table
        // (.returnDateArrives -> .needsAttention), and no RecommendedAction case maps
        // to .returnDateArrives (it is a snooze-timer event, not a card button). So
        // every RecommendedAction should defensively resolve to nil from this state.
        let explanation = explanation(
            recommendedAction: .snooze,
            alternativeActions: [.respond, .plan, .wait, .letGo]
        )

        let presentation = TriagePresentation.build(state: .snoozed, explanation: explanation)

        XCTAssertNil(presentation.recommended, "No RecommendedAction maps to a legal transition from .snoozed")
        XCTAssertTrue(presentation.alternatives.isEmpty)
    }

    // MARK: - Dropped, not crashed: mixed legal/illegal alternatives

    func testIllegalAlternativeIsDroppedWhileLegalOneIsKept() {
        // From .responded, only .wait (-> markAwaitingReply) is legal; .plan and
        // .snooze are not. The mix should silently drop the illegal ones and keep the
        // legal one, never throw or crash.
        let explanation = explanation(
            recommendedAction: .wait,
            alternativeActions: [.plan, .wait, .snooze]
        )

        let presentation = TriagePresentation.build(state: .responded, explanation: explanation)

        XCTAssertEqual(presentation.alternatives.count, 1)
        XCTAssertEqual(
            presentation.alternatives.first,
            TriageResolvedAction(source: .wait, triageAction: .markAwaitingReply, resultingState: .waitingOnThem)
        )
    }

    // MARK: - Concrete example from the task: .wait from .needsAttention -> .waitingOnThem

    func testWaitFromNeedsAttentionResolvesToWaitingOnThem() {
        XCTAssertEqual(
            TriagePresentation.triageAction(for: .wait, from: .needsAttention),
            .markAwaitingReply
        )
        XCTAssertEqual(
            TriageStateMachine.canTransition(from: .needsAttention, via: .markAwaitingReply),
            .waitingOnThem
        )

        let explanation = explanation(recommendedAction: .wait, alternativeActions: [])
        let presentation = TriagePresentation.build(state: .needsAttention, explanation: explanation)
        XCTAssertEqual(presentation.recommended?.resultingState, .waitingOnThem)
    }

    // MARK: - .wait is legal from both states the table allows (needsAttention, responded)

    func testWaitResolvesFromBothLegalSourceStates() {
        XCTAssertEqual(TriagePresentation.triageAction(for: .wait, from: .needsAttention), .markAwaitingReply)
        XCTAssertEqual(TriagePresentation.triageAction(for: .wait, from: .responded), .markAwaitingReply)
        XCTAssertEqual(TriagePresentation.triageAction(for: .wait, from: .planned), nil)
        XCTAssertEqual(TriagePresentation.triageAction(for: .wait, from: .snoozed), nil)
    }

    // MARK: - .letGo is legal from all three states the table allows

    func testLetGoResolvesFromAllThreeLegalSourceStates() {
        XCTAssertEqual(
            TriagePresentation.triageAction(for: .letGo, from: .needsAttention),
            .letGo
        )
        XCTAssertEqual(
            TriagePresentation.triageAction(for: .letGo, from: .planned),
            .letGo
        )
        XCTAssertEqual(
            TriagePresentation.triageAction(for: .letGo, from: .needsANewPlan),
            .letGo
        )
        XCTAssertNil(TriagePresentation.triageAction(for: .letGo, from: .responded))
        XCTAssertNil(TriagePresentation.triageAction(for: .letGo, from: .snoozed))
    }

    // MARK: - Documented open seam: .plan from .needsANewPlan has no legal transition

    func testPlanFromNeedsANewPlanHasNoLegalTransitionYet() {
        // See the doc comment on TriagePresentation.triageAction(for:from:): the
        // canonical table has no (.needsANewPlan, .confirmPlan) row, so "give it a new
        // time" cannot be resolved through the RecommendedAction vocabulary today.
        XCTAssertNil(TriagePresentation.triageAction(for: .plan, from: .needsANewPlan))
    }

    // MARK: - Terminal states have no legal transitions at all

    func testTerminalStatesResolveNothing() {
        for state: Outcome in [.kept, .released] {
            for action in TriageExplanation.RecommendedAction.allCases {
                XCTAssertNil(
                    TriagePresentation.triageAction(for: action, from: state),
                    "\(state) is terminal and should have no legal transition via \(action)"
                )
            }

            let explanation = explanation(recommendedAction: .respond, alternativeActions: TriageExplanation.RecommendedAction.allCases)
            let presentation = TriagePresentation.build(state: state, explanation: explanation)
            XCTAssertNil(presentation.recommended)
            XCTAssertTrue(presentation.alternatives.isEmpty)
        }
    }

    // MARK: - build() preserves state and explanation verbatim

    func testBuildPreservesStateAndExplanation() {
        let explanation = explanation(recommendedAction: .respond, alternativeActions: [.plan])
        let presentation = TriagePresentation.build(state: .needsAttention, explanation: explanation)

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.explanation, explanation)
    }
}
