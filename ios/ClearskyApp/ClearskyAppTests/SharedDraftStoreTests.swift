import XCTest
import ClearskyCore
@testable import ClearskyApp

/// Exercises `SharedDraftStore` against a real `UserDefaults` suite — not the actual
/// App Group (a share extension isn't running in this test process, and the App Group
/// container isn't guaranteed to exist off-device), but real disk-backed `UserDefaults`
/// all the same, which is what makes this a round-trip test rather than a mock. The
/// suite is a throwaway created and removed per test so no run leaks state into another.
final class SharedDraftStoreTests: XCTestCase {
    private static let suiteName = "duck-test-shared-draft-store"

    private var defaults: UserDefaults!
    private var store: SharedDraftStore!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        self.defaults = defaults
        self.store = SharedDraftStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testLoadAllIsEmptyWhenNothingHasBeenCaptured() {
        XCTAssertEqual(store.loadAll(), [])
    }

    func testAppendThenLoadAllReturnsTheDraft() {
        let draft = CapturedPromiseDraft(
            id: "draft-1",
            sharedText: "Pick up the dry cleaning by 5",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .text
        )

        store.append(draft)

        XCTAssertEqual(store.loadAll(), [draft])
    }

    func testAppendKeepsOldestFirstOrder() {
        let first = CapturedPromiseDraft(id: "a", sharedText: "first", capturedAt: Date(), source: .text)
        let second = CapturedPromiseDraft(id: "b", sharedText: "second", capturedAt: Date(), source: .email)

        store.append(first)
        store.append(second)

        XCTAssertEqual(store.loadAll(), [first, second])
    }

    func testRemoveByIdDropsOnlyThatDraft() {
        let keep = CapturedPromiseDraft(id: "keep", sharedText: "keep me", capturedAt: Date(), source: .text)
        let drop = CapturedPromiseDraft(id: "drop", sharedText: "drop me", capturedAt: Date(), source: .text)
        store.append(keep)
        store.append(drop)

        store.remove(id: "drop")

        XCTAssertEqual(store.loadAll(), [keep])
    }

    func testClearEmptiesTheInbox() {
        store.append(CapturedPromiseDraft(id: "a", sharedText: "text", capturedAt: Date(), source: .text))

        store.clear()

        XCTAssertEqual(store.loadAll(), [])
    }

    func testStoreBackedByADifferentDefaultsInstanceOfTheSameSuiteSeesTheSameData() {
        let draft = CapturedPromiseDraft(id: "shared", sharedText: "visible across instances", capturedAt: Date(), source: .email)
        store.append(draft)

        let secondHandle = UserDefaults(suiteName: Self.suiteName)!
        let secondStore = SharedDraftStore(defaults: secondHandle)

        XCTAssertEqual(secondStore.loadAll(), [draft])
    }
}
