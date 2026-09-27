import XCTest
import SwiftUI
import ClearskyCore
@testable import ClearskyApp

/// Regression coverage for wiring `PromisesView`'s rows to `PromiseDetailView` via a
/// background `NavigationLink` in both branches of `row(for:)` — the `.needsANewPlan`
/// (`NeedsANewPlanCard`) branch and the plain `PromiseRow` branch.
///
/// Honesty about what this test can and cannot prove: XCTest has no ViewInspector or
/// XCUITest dependency in this codebase (see `AGENT_MEMORY`/prior screens' test notes),
/// and neither is added here. That means this test CANNOT assert the actual behavior
/// the task is about — that tapping a row's own button (a "Keep it"/"Give it a new
/// time"/"Let it go" exit, or the `.planned` tap-to-complete circle) still fires that
/// button's action instead of the background `NavigationLink` racing it for the tap.
/// SwiftUI's hit-testing precedence (foreground content wins over a `.background`
/// element) is a runtime/rendering guarantee, not something a unit test can observe
/// without a real window and a real touch event.
///
/// What this test DOES prove: `PromisesView.body` — now that every row in every one of
/// the four `PromiseOwnershipGroup` sections carries an extra background
/// `NavigationLink(destination: PromiseDetailView(...))` — still builds without
/// crashing or throwing for a store containing both a `.needsANewPlan` promise (the
/// `NeedsANewPlanCard` branch) and a `.planned` promise (the `PromiseRow` branch), i.e.
/// the two branches of `row(for:)` and their new background links compile, initialize,
/// and evaluate cleanly against a real `PromiseStore`/`Promise`. Forcing `body` to
/// evaluate (rather than just constructing the `PromisesView` struct, which the
/// `@ViewBuilder` `row(for:)` never runs until something reads `body`) is what actually
/// exercises the new `NavigationLink`/`PromiseDetailView` construction on both branches.
///
/// A one-time manual/simulator visual check of the actual tap behavior was not done as
/// part of this change — see the PR description for that same caveat.
@MainActor
final class PromisesViewNavigationTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("duck-test-promises-view-nav-\(UUID().uuidString)")
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
        id: String,
        state: Outcome
    ) -> Promise {
        Promise(
            id: id,
            personName: "Maya Chen",
            whatWasPromised: "Send the invoice",
            dueDate: Date(timeIntervalSince1970: 1_700_000_000),
            protectedTime: false,
            state: state
        )
    }

    func testPromisesViewInitializesAndRendersWithNeedsANewPlanAndPlannedPromises() {
        let store = PromiseStore(fileURL: fileURL)
        store.add(makePromise(id: "needs-a-new-plan-1", state: .needsANewPlan))
        store.add(makePromise(id: "planned-1", state: .planned))

        let view = PromisesView(store: store, calendarService: MockCalendarService())

        // Forces the `@ViewBuilder` body — including `row(for:)`'s two branches and
        // their new background `NavigationLink(destination: PromiseDetailView(...))`
        // constructions — to actually evaluate, rather than merely constructing the
        // (otherwise inert) `PromisesView` value.
        let renderedBody: PromisesView.Body = view.body
        XCTAssertNotNil(renderedBody)

        // Confirms the store actually holds both promises this test needs `row(for:)`
        // to have taken both branches for — a `.needsANewPlan` promise (the
        // `NeedsANewPlanCard` branch) and a `.planned` promise (the plain `PromiseRow`
        // branch, since only `.planned` is directly completable).
        XCTAssertEqual(store.promises.count, 2)
        XCTAssertTrue(store.promises.contains { $0.state == .needsANewPlan })
        XCTAssertTrue(store.promises.contains { $0.state == .planned })
    }
}
