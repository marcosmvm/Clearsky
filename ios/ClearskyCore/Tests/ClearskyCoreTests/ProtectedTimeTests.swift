import XCTest
@testable import ClearskyCore

final class ProtectedTimeTests: XCTestCase {

    // MARK: - CalendarItemKind is the closed, three-case vocabulary the audit doc names

    func testCalendarItemKindHasExactlyThreeCasesMatchingTheAuditDoc() {
        let expected: Set<CalendarItemKind> = [.promise, .externalEvent, .protectedBlock]
        XCTAssertEqual(CalendarItemKind.allCases.count, 3)
        XCTAssertEqual(Set(CalendarItemKind.allCases), expected)
    }

    // MARK: - A protected block is distinguishable from a promise/external event

    func testProtectedTimeBlockAlwaysReportsTheProtectedBlockKind() {
        let block = ProtectedTimeBlock(
            id: "block-1",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_007_200),
            ownerTitle: "Protected evening",
            ownerDetail: "Nothing can land here"
        )
        XCTAssertEqual(block.kind, .protectedBlock)
        XCTAssertNotEqual(block.kind, .promise)
        XCTAssertNotEqual(block.kind, .externalEvent)
    }

    func testCalendarItemKindCasesAreAllMutuallyDistinct() {
        // A protected block's kind must never collide with either of the other two
        // calendar representations the audit doc requires distinguishing.
        XCTAssertNotEqual(CalendarItemKind.protectedBlock, CalendarItemKind.promise)
        XCTAssertNotEqual(CalendarItemKind.protectedBlock, CalendarItemKind.externalEvent)
        XCTAssertNotEqual(CalendarItemKind.promise, CalendarItemKind.externalEvent)
    }

    // MARK: - Owner presentation reveals the real title/detail

    func testOwnerPresentationRevealsTheRealTitleAndDetail() {
        let block = ProtectedTimeBlock(
            id: "block-2",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_007_200),
            ownerTitle: "Dinner with Jamie",
            ownerDetail: "At Nido — don't schedule over this"
        )

        let presentation = ProtectedTimePresentation.resolve(block, for: .owner)

        XCTAssertEqual(presentation.title, "Dinner with Jamie")
        XCTAssertEqual(presentation.detail, "At Nido — don't schedule over this")
        XCTAssertTrue(presentation.revealsOwnerDetails)
    }

    // MARK: - Other-viewer presentation never leaks the real title/details

    func testOtherViewerPresentationShowsOnlyBusyWithNoDetails() {
        let block = ProtectedTimeBlock(
            id: "block-3",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_007_200),
            ownerTitle: "Dinner with Jamie",
            ownerDetail: "At Nido — don't schedule over this"
        )

        let presentation = ProtectedTimePresentation.resolve(block, for: .otherViewer)

        XCTAssertEqual(presentation.title, ProtectedTimePresentation.busyLabelForOtherViewers)
        XCTAssertNil(presentation.detail)
        XCTAssertFalse(presentation.revealsOwnerDetails)

        // Explicit leak checks: the real title/detail must never appear anywhere in
        // what an other viewer is given.
        XCTAssertNotEqual(presentation.title, block.ownerTitle)
        XCTAssertFalse(presentation.title.contains(block.ownerTitle))
    }

    func testOtherViewerNeverSeesOwnerDetailsRegardlessOfBlockContent() {
        // Vary the owner-authored content across several blocks; the other-viewer
        // presentation must be identical every time ("Busy", no detail) — never a
        // function of what the block actually says.
        let blocks = [
            ProtectedTimeBlock(
                id: "a", start: Date(), end: Date().addingTimeInterval(3600),
                ownerTitle: "Therapy", ownerDetail: "Dr. Alvarez, downtown"
            ),
            ProtectedTimeBlock(
                id: "b", start: Date(), end: Date().addingTimeInterval(3600),
                ownerTitle: "Deep work", ownerDetail: "Notifications paused"
            ),
            ProtectedTimeBlock(
                id: "c", start: Date(), end: Date().addingTimeInterval(3600),
                ownerTitle: "", ownerDetail: ""
            )
        ]

        for block in blocks {
            let presentation = ProtectedTimePresentation.resolve(block, for: .otherViewer)
            XCTAssertEqual(presentation.title, "Busy")
            XCTAssertNil(presentation.detail)
            XCTAssertFalse(presentation.revealsOwnerDetails)
        }
    }

    func testOwnerAndOtherViewerPresentationsDifferForTheSameBlock() {
        let block = ProtectedTimeBlock(
            id: "block-4",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_007_200),
            ownerTitle: "Protected evening",
            ownerDetail: "Nothing can land here"
        )

        let ownerView = ProtectedTimePresentation.resolve(block, for: .owner)
        let otherView = ProtectedTimePresentation.resolve(block, for: .otherViewer)

        XCTAssertNotEqual(ownerView, otherView)
    }

    // MARK: - Codable round-trip

    func testProtectedTimeBlockRoundTripsThroughCodable() throws {
        let block = ProtectedTimeBlock(
            id: "block-5",
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_007_200),
            ownerTitle: "Protected evening",
            ownerDetail: "Nothing can land here"
        )

        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(ProtectedTimeBlock.self, from: data)

        XCTAssertEqual(decoded, block)
    }
}
