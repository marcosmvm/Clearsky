import XCTest
@testable import ClearskyCore

final class PromiseTests: XCTestCase {

    func testConstructionKeepsFieldsAsGivenAndDefaultsStateToPlanned() {
        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        let promise = Promise(
            id: "promise-1",
            personName: "Maya Chen",
            whatWasPromised: "Send the invoice",
            dueDate: dueDate,
            protectedTime: true
        )

        XCTAssertEqual(promise.id, "promise-1")
        XCTAssertEqual(promise.personName, "Maya Chen")
        XCTAssertEqual(promise.whatWasPromised, "Send the invoice")
        XCTAssertEqual(promise.dueDate, dueDate)
        XCTAssertNil(promise.sourceText)
        XCTAssertTrue(promise.protectedTime)
        XCTAssertEqual(promise.state, .planned)
    }

    func testConstructionAcceptsExplicitSourceTextAndState() {
        let promise = Promise(
            id: "promise-2",
            personName: "James Okafor",
            whatWasPromised: "Follow up on the intro doc",
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            sourceText: "Hey, any read on that doc I sent?",
            protectedTime: false,
            state: .kept
        )

        XCTAssertEqual(promise.sourceText, "Hey, any read on that doc I sent?")
        XCTAssertFalse(promise.protectedTime)
        XCTAssertEqual(promise.state, .kept)
    }

    func testTwoPromisesWithSameFieldsAreEqual() {
        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Promise(id: "p1", personName: "Maya Chen", whatWasPromised: "Call back", dueDate: dueDate, protectedTime: false)
        let b = Promise(id: "p1", personName: "Maya Chen", whatWasPromised: "Call back", dueDate: dueDate, protectedTime: false)

        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testPromisesWithDifferentIdsAreNotEqual() {
        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Promise(id: "p1", personName: "Maya Chen", whatWasPromised: "Call back", dueDate: dueDate, protectedTime: false)
        let b = Promise(id: "p2", personName: "Maya Chen", whatWasPromised: "Call back", dueDate: dueDate, protectedTime: false)

        XCTAssertNotEqual(a, b)
    }

    func testStateCanBeMutatedAfterCreation() {
        var promise = Promise(
            id: "promise-3",
            personName: "Maya Chen",
            whatWasPromised: "Book the table",
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            protectedTime: false
        )
        XCTAssertEqual(promise.state, .planned)

        promise.state = .needsANewPlan

        XCTAssertEqual(promise.state, .needsANewPlan)
    }

    func testPromiseRoundTripsThroughJSONCoding() throws {
        let original = Promise(
            id: "promise-4",
            personName: "Priya Nair",
            whatWasPromised: "Confirm Saturday's pickup time",
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            sourceText: "Let's confirm Saturday's pickup time",
            protectedTime: true,
            state: .planned
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Promise.self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testPromiseWithNilSourceTextRoundTripsThroughJSONCoding() throws {
        let original = Promise(
            id: "promise-5",
            personName: "Priya Nair",
            whatWasPromised: "Hand-entered promise",
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            protectedTime: false
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Promise.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.sourceText)
    }

    func testArrayOfPromisesRoundTripsThroughJSONCoding() throws {
        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        let promises = [
            Promise(id: "p1", personName: "Maya Chen", whatWasPromised: "Call back", dueDate: dueDate, protectedTime: false),
            Promise(id: "p2", personName: "James Okafor", whatWasPromised: "Send file", dueDate: dueDate, sourceText: "please send", protectedTime: true, state: .kept)
        ]

        let encoded = try JSONEncoder().encode(promises)
        let decoded = try JSONDecoder().decode([Promise].self, from: encoded)

        XCTAssertEqual(decoded, promises)
    }

    // MARK: - calendarEventIdentifier

    /// `calendarEventIdentifier` is the one additive field this task adds to
    /// `Promise` (see the type's doc comment): it defaults to `nil` for a promise
    /// with no calendar hold, and it round-trips through `Codable` both when set (a
    /// hold was created) and when left `nil` — the same JSON persistence
    /// `PromiseStore` already relies on for every other field.
    func testCalendarEventIdentifierDefaultsToNilAndRoundTripsThroughJSONCoding() throws {
        let withoutHold = Promise(
            id: "promise-6",
            personName: "Maya Chen",
            whatWasPromised: "Send the invoice",
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            protectedTime: true
        )
        XCTAssertNil(withoutHold.calendarEventIdentifier)

        let decodedWithoutHold = try JSONDecoder().decode(Promise.self, from: JSONEncoder().encode(withoutHold))
        XCTAssertEqual(decodedWithoutHold, withoutHold)
        XCTAssertNil(decodedWithoutHold.calendarEventIdentifier)

        let withHold = Promise(
            id: "promise-7",
            personName: "James Okafor",
            whatWasPromised: "Call about the lease renewal",
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            protectedTime: true,
            state: .planned,
            calendarEventIdentifier: "event-abc-123"
        )

        let decodedWithHold = try JSONDecoder().decode(Promise.self, from: JSONEncoder().encode(withHold))
        XCTAssertEqual(decodedWithHold, withHold)
        XCTAssertEqual(decodedWithHold.calendarEventIdentifier, "event-abc-123")
    }
}
