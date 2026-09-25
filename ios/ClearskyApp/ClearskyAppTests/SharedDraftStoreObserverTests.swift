import XCTest
import Combine
import ClearskyCore
@testable import ClearskyApp

/// Exercises `SharedDraftStoreObserver`'s live-observation behavior — the actual bug
/// this task fixes — against a real, disposable `UserDefaults` suite, mirroring
/// `SharedDraftStoreTests`'s isolation pattern for the underlying `SharedDraftStore`.
/// Each test gets its own throwaway suite, removed in `tearDown` so no run leaks state
/// into another.
@MainActor
final class SharedDraftStoreObserverTests: XCTestCase {
    private static let suiteName = "duck-test-shared-draft-store-observer"

    private var defaults: UserDefaults!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        self.defaults = defaults
    }

    override func tearDown() {
        cancellables.removeAll()
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        super.tearDown()
    }

    func testInitialDraftsReflectWhatWasAlreadyInTheStore() {
        let seedStore = SharedDraftStore(defaults: defaults)
        let existing = CapturedPromiseDraft(
            id: "existing",
            sharedText: "already captured before the observer existed",
            capturedAt: Date(),
            source: .text
        )
        seedStore.append(existing)

        let observer = SharedDraftStoreObserver(store: SharedDraftStore(defaults: defaults), defaults: defaults)

        XCTAssertEqual(observer.drafts, [existing])
        XCTAssertEqual(observer.count, 1)
    }

    /// The behavior this task exists to prove: a draft appended through a plain,
    /// separate `SharedDraftStore(defaults:)` call — NOT through the observer's own
    /// `remove(id:)` or any other method it exposes — shows up in the observer's
    /// `drafts` with no explicit `refresh()`/`reload()` call from this test.
    ///
    /// That separate `SharedDraftStore` call is built over the exact same
    /// `UserDefaults` *instance* (`defaults`) the observer was constructed with —
    /// deliberately, not just the same suite name. Two reasons:
    ///   1. `NotificationCenter` notifications never cross process boundaries, so a
    ///      real Share-Extension write (a different process entirely) can't be
    ///      reproduced by a unit test running in one process no matter what — the
    ///      production mechanism for that case is `UserDefaults` itself detecting an
    ///      external change and re-posting `didChangeNotification` once the app
    ///      returns to the foreground, which is a real but not deterministically
    ///      unit-testable OS behavior.
    ///   2. Within one process, `NotificationCenter`'s `object:` filter matches by
    ///      identity — a notification posted by a *different* `UserDefaults` object
    ///      (even backed by the same suite name on disk) would not reach a
    ///      subscription scoped to `object: defaults`. Using the same instance is
    ///      what actually exercises the observer's subscription, and is the honest
    ///      in-process analogue of "some other code path wrote to this store without
    ///      going through the observer" — exactly what the Share Extension does in
    ///      practice, just within this test's single process instead of two.
    ///
    /// `SharedDraftStoreObserver` routes the notification through
    /// `.receive(on: DispatchQueue.main)` (defensive against a future write
    /// happening off the main thread), which schedules the `drafts` update as a
    /// dispatched block for the next main run loop turn rather than inline in this
    /// call stack — so this test waits on an `XCTestExpectation`, fulfilled from a
    /// `$drafts` subscription, instead of asserting immediately after `append`.
    func testDraftsUpdatesWhenAnotherStoreInstanceAppendsToTheSameUserDefaults() {
        let observer = SharedDraftStoreObserver(store: SharedDraftStore(defaults: defaults), defaults: defaults)
        XCTAssertEqual(observer.drafts, [])

        let updated = expectation(description: "observer.drafts updates after an external append")
        observer.$drafts
            .dropFirst() // the initial (empty) value `$drafts` resends immediately on subscribe
            .sink { drafts in
                if !drafts.isEmpty {
                    updated.fulfill()
                }
            }
            .store(in: &cancellables)

        let newDraft = CapturedPromiseDraft(
            id: "from-share-extension",
            sharedText: "Can you send the invoice by Friday?",
            capturedAt: Date(),
            source: .text
        )
        // Simulates the Share Extension's write path: a brand new `SharedDraftStore`
        // value, never touching `observer` or its wrapped `store` directly.
        SharedDraftStore(defaults: defaults).append(newDraft)

        wait(for: [updated], timeout: 2.0)

        XCTAssertEqual(observer.drafts, [newDraft])
        XCTAssertEqual(observer.count, 1)
    }

    func testRemoveDropsOnlyThatDraftAndUpdatesDraftsImmediately() {
        let seedStore = SharedDraftStore(defaults: defaults)
        let keep = CapturedPromiseDraft(id: "keep", sharedText: "keep me", capturedAt: Date(), source: .text)
        let drop = CapturedPromiseDraft(id: "drop", sharedText: "drop me", capturedAt: Date(), source: .text)
        seedStore.append(keep)
        seedStore.append(drop)

        let observer = SharedDraftStoreObserver(store: SharedDraftStore(defaults: defaults), defaults: defaults)
        XCTAssertEqual(observer.drafts, [keep, drop])

        observer.remove(id: "drop")

        // No expectation/wait needed here: `remove(id:)` reloads synchronously itself
        // (see its doc comment) rather than relying on the notification round trip.
        XCTAssertEqual(observer.drafts, [keep])
        XCTAssertEqual(observer.count, 1)
    }
}
