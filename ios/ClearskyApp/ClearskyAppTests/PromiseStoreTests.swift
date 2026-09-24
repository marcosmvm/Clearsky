import XCTest
import ClearskyCore
@testable import ClearskyApp

/// Exercises `PromiseStore` against a real temp file on disk — not a mock — so this is
/// a genuine round-trip test of the JSON persistence, same spirit as
/// `SharedDraftStoreTests` for `SharedDraftStore`. Each test gets its own throwaway
/// file, removed in `tearDown` so no run leaks state into another.
@MainActor
final class PromiseStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("duck-test-promise-store-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    override func tearDown() {
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        super.tearDown()
    }

    private func makePromise(
        id: String = "promise-1",
        personName: String = "Maya Chen",
        whatWasPromised: String = "Send the invoice",
        state: Outcome = .planned
    ) -> Promise {
        Promise(
            id: id,
            personName: personName,
            whatWasPromised: whatWasPromised,
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            protectedTime: false,
            state: state
        )
    }

    func testStartsEmptyWhenNoFileExistsYet() {
        let store = PromiseStore(fileURL: fileURL)

        XCTAssertEqual(store.promises, [])
    }

    func testAddAppendsAndPublishesThePromise() {
        let store = PromiseStore(fileURL: fileURL)
        let promise = makePromise()

        store.add(promise)

        XCTAssertEqual(store.promises, [promise])
    }

    func testUpdateReplacesThePromiseWithMatchingId() {
        let store = PromiseStore(fileURL: fileURL)
        let original = makePromise(state: .planned)
        store.add(original)

        var edited = original
        edited.state = .kept
        store.update(edited)

        XCTAssertEqual(store.promises, [edited])
        XCTAssertEqual(store.promises.first?.state, .kept)
    }

    func testUpdateWithUnknownIdIsANoOp() {
        let store = PromiseStore(fileURL: fileURL)
        let existing = makePromise(id: "existing")
        store.add(existing)

        let unknown = makePromise(id: "unknown")
        store.update(unknown)

        XCTAssertEqual(store.promises, [existing])
    }

    func testAddPersistsToDiskAndANewStoreInstanceLoadsIt() {
        let firstStore = PromiseStore(fileURL: fileURL)
        let promise = makePromise()
        firstStore.add(promise)

        let secondStore = PromiseStore(fileURL: fileURL)

        XCTAssertEqual(secondStore.promises, [promise])
    }

    func testUpdatePersistsToDiskAndANewStoreInstanceLoadsIt() {
        let firstStore = PromiseStore(fileURL: fileURL)
        let promise = makePromise(state: .planned)
        firstStore.add(promise)

        var edited = promise
        edited.state = .needsANewPlan
        firstStore.update(edited)

        let secondStore = PromiseStore(fileURL: fileURL)

        XCTAssertEqual(secondStore.promises, [edited])
    }

    func testAddKeepsInsertionOrder() {
        let store = PromiseStore(fileURL: fileURL)
        let first = makePromise(id: "a")
        let second = makePromise(id: "b")

        store.add(first)
        store.add(second)

        XCTAssertEqual(store.promises, [first, second])
    }
}
