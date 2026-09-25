import XCTest
import ClearskyCore
@testable import ClearskyApp

/// Exercises `PromiseStore.deleteAll()`, `PrivacyArchiveExporter.exportJSON(_:)` and
/// `PrivacyViewModel` — the view-independent logic behind `PrivacyView` — against
/// real, disposable stores (a temp file for `PromiseStore`, a throwaway `UserDefaults`
/// suite for `SharedDraftStore`), never mocks: neither store is protocol-based, so
/// proving "the two-step delete calls both" means asserting on each store's real,
/// observable effect after the action runs — same "round trip against a real store"
/// spirit `PromiseStoreTests`/`SharedDraftStoreTests` already use.
@MainActor
final class PrivacyViewModelTests: XCTestCase {
    private static let draftSuiteName = "duck-test-privacy-view-model-drafts"

    private var promiseStoreFileURL: URL!
    private var draftDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        promiseStoreFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("duck-test-privacy-view-model-promises-\(UUID().uuidString)")
            .appendingPathExtension("json")
        draftDefaults = UserDefaults(suiteName: Self.draftSuiteName)!
        draftDefaults.removePersistentDomain(forName: Self.draftSuiteName)
    }

    override func tearDown() {
        if let promiseStoreFileURL {
            try? FileManager.default.removeItem(at: promiseStoreFileURL)
        }
        promiseStoreFileURL = nil
        draftDefaults.removePersistentDomain(forName: Self.draftSuiteName)
        draftDefaults = nil
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

    private func makeDraft(id: String = "draft-1") -> CapturedPromiseDraft {
        CapturedPromiseDraft(
            id: id,
            sharedText: "Pick up the dry cleaning by 5",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .text
        )
    }

    // MARK: - PromiseStore.deleteAll()

    func testDeleteAllEmptiesPromisesAndPublishes() {
        let store = PromiseStore(fileURL: promiseStoreFileURL)
        store.add(makePromise(id: "a"))
        store.add(makePromise(id: "b"))

        store.deleteAll()

        XCTAssertEqual(store.promises, [])
    }

    func testDeleteAllPersistsToDiskAndANewStoreInstanceLoadsEmpty() {
        let firstStore = PromiseStore(fileURL: promiseStoreFileURL)
        firstStore.add(makePromise())

        firstStore.deleteAll()

        let secondStore = PromiseStore(fileURL: promiseStoreFileURL)
        XCTAssertEqual(secondStore.promises, [])
    }

    func testDeleteAllOnAnAlreadyEmptyStoreIsANoOpThatStillPersists() {
        let store = PromiseStore(fileURL: promiseStoreFileURL)

        store.deleteAll()

        let secondStore = PromiseStore(fileURL: promiseStoreFileURL)
        XCTAssertEqual(store.promises, [])
        XCTAssertEqual(secondStore.promises, [])
    }

    // MARK: - PrivacyArchiveExporter

    func testExportJSONOfNoPromisesDecodesToAnEmptyArray() throws {
        let json = PrivacyArchiveExporter.exportJSON([])

        let decoded = try JSONDecoder().decode([Promise].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, [])
    }

    func testExportJSONRoundTripsTheActualPromises() throws {
        let promises = [makePromise(id: "a"), makePromise(id: "b", personName: "James Okafor")]

        let json = PrivacyArchiveExporter.exportJSON(promises)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Promise].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, promises)
    }

    // MARK: - PrivacyViewModel: requestDelete() (first tap) deletes nothing

    func testRequestDeleteOnlyShowsConfirmationAndDeletesNothing() {
        let store = PromiseStore(fileURL: promiseStoreFileURL)
        store.add(makePromise())
        let draftStore = SharedDraftStore(defaults: draftDefaults)
        draftStore.append(makeDraft())
        let viewModel = PrivacyViewModel(store: store, sharedDraftStore: draftStore)

        viewModel.requestDelete()

        XCTAssertTrue(viewModel.isShowingDeleteConfirmation)
        XCTAssertFalse(viewModel.didDeleteEverything)
        XCTAssertEqual(store.promises.count, 1)
        XCTAssertEqual(draftStore.loadAll().count, 1)
    }

    func testCancelDeleteHidesConfirmationAndDeletesNothing() {
        let store = PromiseStore(fileURL: promiseStoreFileURL)
        store.add(makePromise())
        let draftStore = SharedDraftStore(defaults: draftDefaults)
        draftStore.append(makeDraft())
        let viewModel = PrivacyViewModel(store: store, sharedDraftStore: draftStore)
        viewModel.requestDelete()

        viewModel.cancelDelete()

        XCTAssertFalse(viewModel.isShowingDeleteConfirmation)
        XCTAssertFalse(viewModel.didDeleteEverything)
        XCTAssertEqual(store.promises.count, 1)
        XCTAssertEqual(draftStore.loadAll().count, 1)
    }

    // MARK: - PrivacyViewModel: confirmDeleteEverything() (second tap) calls both

    func testConfirmDeleteEverythingEmptiesBothPromisesAndPendingDrafts() {
        let store = PromiseStore(fileURL: promiseStoreFileURL)
        store.add(makePromise(id: "a"))
        store.add(makePromise(id: "b"))
        let draftStore = SharedDraftStore(defaults: draftDefaults)
        draftStore.append(makeDraft(id: "draft-a"))
        draftStore.append(makeDraft(id: "draft-b"))
        let viewModel = PrivacyViewModel(store: store, sharedDraftStore: draftStore)
        viewModel.requestDelete()

        viewModel.confirmDeleteEverything(now: Date(timeIntervalSince1970: 1_700_000_000))

        // Both stores were actually touched, not just one of the two.
        XCTAssertEqual(store.promises, [])
        XCTAssertEqual(draftStore.loadAll(), [])
    }

    func testConfirmDeleteEverythingPersistsBothDeletionsToDisk() {
        let store = PromiseStore(fileURL: promiseStoreFileURL)
        store.add(makePromise())
        let draftStore = SharedDraftStore(defaults: draftDefaults)
        draftStore.append(makeDraft())
        let viewModel = PrivacyViewModel(store: store, sharedDraftStore: draftStore)

        viewModel.confirmDeleteEverything()

        // A fresh instance of each store, backed by the same file/suite, also sees
        // the deletion — proving it was actually persisted, not just held in memory.
        let reloadedStore = PromiseStore(fileURL: promiseStoreFileURL)
        let reloadedDraftDefaults = UserDefaults(suiteName: Self.draftSuiteName)!
        let reloadedDraftStore = SharedDraftStore(defaults: reloadedDraftDefaults)
        XCTAssertEqual(reloadedStore.promises, [])
        XCTAssertEqual(reloadedDraftStore.loadAll(), [])
    }

    func testConfirmDeleteEverythingUpdatesViewModelStateAndClosesTheDialog() {
        let store = PromiseStore(fileURL: promiseStoreFileURL)
        store.add(makePromise())
        let draftStore = SharedDraftStore(defaults: draftDefaults)
        let viewModel = PrivacyViewModel(store: store, sharedDraftStore: draftStore)
        viewModel.requestDelete()
        let deletionInstant = Date(timeIntervalSince1970: 1_700_000_000)

        viewModel.confirmDeleteEverything(now: deletionInstant)

        XCTAssertTrue(viewModel.didDeleteEverything)
        XCTAssertEqual(viewModel.deletedAt, deletionInstant)
        XCTAssertFalse(viewModel.isShowingDeleteConfirmation)
    }

    func testArchiveExportTextReflectsTheLiveStoreAtEachRead() throws {
        let store = PromiseStore(fileURL: promiseStoreFileURL)
        let draftStore = SharedDraftStore(defaults: draftDefaults)
        let viewModel = PrivacyViewModel(store: store, sharedDraftStore: draftStore)

        let emptyDecoded = try JSONDecoder().decode([Promise].self, from: Data(viewModel.archiveExportText.utf8))
        XCTAssertEqual(emptyDecoded, [])

        store.add(makePromise(id: "a", personName: "Priya Patel"))

        XCTAssertTrue(viewModel.archiveExportText.contains("Priya Patel"))
    }
}
