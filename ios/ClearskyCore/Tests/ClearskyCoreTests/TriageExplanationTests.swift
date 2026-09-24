import XCTest
@testable import ClearskyCore

final class TriageExplanationTests: XCTestCase {

    func testSignalCasesMatchSpec() {
        let expected: Set<TriageExplanation.Signal> = [
            .innerCircle, .directQuestion, .promiseDue, .waitingDuration, .recentChange, .snoozeReturn
        ]
        XCTAssertEqual(TriageExplanation.Signal.allCases.count, 6)
        XCTAssertEqual(Set(TriageExplanation.Signal.allCases), expected)
    }

    func testRecommendedActionCasesMatchSpec() {
        let expected: Set<TriageExplanation.RecommendedAction> = [
            .respond, .plan, .snooze, .wait, .letGo
        ]
        XCTAssertEqual(TriageExplanation.RecommendedAction.allCases.count, 5)
        XCTAssertEqual(Set(TriageExplanation.RecommendedAction.allCases), expected)
    }

    func testConstructsWithClosedSetActionsOnly() {
        let explanation = TriageExplanation(
            whyNow: "Inner circle · asked you a direct question · waiting 3 days",
            signals: [.innerCircle, .directQuestion, .waitingDuration],
            ifNoAction: "It stays in Needs attention and resurfaces tomorrow morning.",
            nextReviewAt: nil,
            recommendedAction: .respond,
            alternativeActions: [.plan, .snooze]
        )

        XCTAssertEqual(explanation.recommendedAction, .respond)
        XCTAssertEqual(explanation.alternativeActions, [.plan, .snooze])
        XCTAssertEqual(explanation.signals, [.innerCircle, .directQuestion, .waitingDuration])
        XCTAssertNil(explanation.nextReviewAt)
    }

    func testNextReviewAtIsOptionalButSettable() {
        let reviewDate = Date(timeIntervalSince1970: 1_700_000_000)
        let explanation = TriageExplanation(
            whyNow: "Snooze return · you chose to revisit this today.",
            signals: [.snoozeReturn],
            ifNoAction: "It will sit in Needs attention until you act.",
            nextReviewAt: reviewDate,
            recommendedAction: .plan,
            alternativeActions: [.snooze, .letGo]
        )

        XCTAssertEqual(explanation.nextReviewAt, reviewDate)
    }
}
