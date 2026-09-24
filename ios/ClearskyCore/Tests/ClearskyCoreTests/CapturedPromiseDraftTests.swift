import XCTest
@testable import ClearskyCore

final class CapturedPromiseDraftTests: XCTestCase {

    func testConstructionKeepsFieldsAsGiven() {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = CapturedPromiseDraft(
            id: "draft-1",
            sharedText: "Can you send the invoice by Friday?",
            capturedAt: capturedAt,
            source: .text
        )

        XCTAssertEqual(draft.id, "draft-1")
        XCTAssertEqual(draft.sharedText, "Can you send the invoice by Friday?")
        XCTAssertEqual(draft.capturedAt, capturedAt)
        XCTAssertEqual(draft.source, .text)
    }

    func testTwoDraftsWithSameFieldsAreEqual() {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CapturedPromiseDraft(id: "draft-1", sharedText: "same text", capturedAt: capturedAt, source: .email)
        let b = CapturedPromiseDraft(id: "draft-1", sharedText: "same text", capturedAt: capturedAt, source: .email)

        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testDraftsWithDifferentIdsAreNotEqual() {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let a = CapturedPromiseDraft(id: "draft-1", sharedText: "same text", capturedAt: capturedAt, source: .text)
        let b = CapturedPromiseDraft(id: "draft-2", sharedText: "same text", capturedAt: capturedAt, source: .text)

        XCTAssertNotEqual(a, b)
    }

    func testBothSourceCasesExist() {
        XCTAssertEqual(CapturedPromiseSource.allCases.count, 2)
        XCTAssertEqual(Set(CapturedPromiseSource.allCases), [.text, .email])
    }

    func testDraftRoundTripsThroughJSONCoding() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = CapturedPromiseDraft(
            id: "draft-1",
            sharedText: "Let's confirm Saturday's pickup time",
            capturedAt: capturedAt,
            source: .email
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CapturedPromiseDraft.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testArrayOfDraftsRoundTripsThroughJSONCoding() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let drafts = [
            CapturedPromiseDraft(id: "draft-1", sharedText: "first", capturedAt: capturedAt, source: .text),
            CapturedPromiseDraft(id: "draft-2", sharedText: "second", capturedAt: capturedAt, source: .email)
        ]

        let encoded = try JSONEncoder().encode(drafts)
        let decoded = try JSONDecoder().decode([CapturedPromiseDraft].self, from: encoded)

        XCTAssertEqual(decoded, drafts)
    }
}
