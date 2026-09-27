import XCTest
import ClearskyCore
@testable import ClearskyApp

/// Exercises the genuinely testable surface behind `YouView`: the three `@AppStorage`
/// keys' exact string values (`calendarConnected` in particular is also written by a
/// separate, parallel task this shift — the two only interoperate if the key strings
/// match verbatim), the toggle-backed properties' real round trip through an injected,
/// disposable `UserDefaults` suite, and the pure `YouConnectedAccountsDisplay` text
/// function. No SwiftUI rendering is exercised or claimed to be tested here — same
/// "prove the real, observable effect" spirit `PrivacyViewModelTests` already uses.
@MainActor
final class YouViewTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var promiseStoreFileURL: URL!

    override func setUp() {
        super.setUp()
        suiteName = "duck-test-you-view-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        promiseStoreFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("duck-test-you-view-promises-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        if let promiseStoreFileURL {
            try? FileManager.default.removeItem(at: promiseStoreFileURL)
        }
        promiseStoreFileURL = nil
        super.tearDown()
    }

    private func makeStore() -> PromiseStore {
        PromiseStore(fileURL: promiseStoreFileURL)
    }

    private func makeSharedDraftStore() -> SharedDraftStore {
        let draftSuiteName = "duck-test-you-view-drafts-\(UUID().uuidString)"
        let draftDefaults = UserDefaults(suiteName: draftSuiteName)!
        return SharedDraftStore(defaults: draftDefaults)
    }

    // MARK: - Key strings

    /// Pins the exact `UserDefaults` key strings this screen uses. `calendarConnected`
    /// is written by a different, parallel task this shift (the first-run Connect
    /// calendar flow) via this same literal string — this test guards against either
    /// side silently renaming it and breaking that interop.
    func test_defaultsKeys_matchExactStrings() {
        XCTAssertEqual(YouViewDefaultsKey.morningSummaryEnabled, "morningSummaryEnabled")
        XCTAssertEqual(YouViewDefaultsKey.protectEveningsEnabled, "protectEveningsEnabled")
        XCTAssertEqual(YouViewDefaultsKey.calendarConnected, "calendarConnected")
    }

    // MARK: - morningSummaryEnabled

    func test_morningSummaryEnabled_defaultsToTrue() {
        let view = YouView(store: makeStore(), sharedDraftStore: makeSharedDraftStore(), defaults: defaults)
        XCTAssertTrue(view.morningSummaryEnabled)
    }

    /// Proves the real `@AppStorage` property — not a hand-rolled parallel call —
    /// writes through to the exact injected `UserDefaults` suite under the exact key,
    /// and that a second `YouView` instance built over the same suite reads the
    /// persisted value back. Neither instance ever touches `.standard`.
    func test_morningSummaryEnabled_roundTripsThroughInjectedDefaults() {
        var view = YouView(store: makeStore(), sharedDraftStore: makeSharedDraftStore(), defaults: defaults)

        view.morningSummaryEnabled = false

        XCTAssertFalse(defaults.bool(forKey: YouViewDefaultsKey.morningSummaryEnabled))

        let secondView = YouView(store: makeStore(), sharedDraftStore: makeSharedDraftStore(), defaults: defaults)
        XCTAssertFalse(secondView.morningSummaryEnabled)
    }

    // MARK: - protectEveningsEnabled

    func test_protectEveningsEnabled_defaultsToFalse() {
        let view = YouView(store: makeStore(), sharedDraftStore: makeSharedDraftStore(), defaults: defaults)
        XCTAssertFalse(view.protectEveningsEnabled)
    }

    func test_protectEveningsEnabled_roundTripsThroughInjectedDefaults() {
        var view = YouView(store: makeStore(), sharedDraftStore: makeSharedDraftStore(), defaults: defaults)

        view.protectEveningsEnabled = true

        XCTAssertTrue(defaults.bool(forKey: YouViewDefaultsKey.protectEveningsEnabled))

        let secondView = YouView(store: makeStore(), sharedDraftStore: makeSharedDraftStore(), defaults: defaults)
        XCTAssertTrue(secondView.protectEveningsEnabled)
    }

    // MARK: - calendarConnected (read-only in this screen)

    func test_calendarConnected_defaultsToFalse() {
        let view = YouView(store: makeStore(), sharedDraftStore: makeSharedDraftStore(), defaults: defaults)
        XCTAssertFalse(view.calendarConnected)
    }

    /// Simulates the separate, parallel task this shift that sets `calendarConnected`
    /// true once calendar access is granted during first run — writing directly to the
    /// suite under the exact key string, the same way that task's own code would,
    /// entirely independent of `YouView`. Confirms `YouView` reads that value back
    /// rather than caching a stale default.
    func test_calendarConnected_readsValueWrittenByAnotherWriter() {
        defaults.set(true, forKey: YouViewDefaultsKey.calendarConnected)

        let view = YouView(store: makeStore(), sharedDraftStore: makeSharedDraftStore(), defaults: defaults)

        XCTAssertTrue(view.calendarConnected)
    }

    // MARK: - YouConnectedAccountsDisplay (pure function, no UserDefaults involved)

    func test_calendarStatusText_whenConnected() {
        XCTAssertEqual(
            YouConnectedAccountsDisplay.calendarStatusText(connected: true),
            "Calendar \u{2014} Connected"
        )
    }

    func test_calendarStatusText_whenNotConnected() {
        XCTAssertEqual(
            YouConnectedAccountsDisplay.calendarStatusText(connected: false),
            "Calendar \u{2014} Not connected"
        )
    }
}
