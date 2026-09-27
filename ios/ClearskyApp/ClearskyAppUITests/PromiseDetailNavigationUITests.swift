import XCTest

/// Real XCUITest for Promise row tap-through navigation to `PromiseDetailView`.
///
/// This is a genuinely different kind of proof than `PromisesViewNavigationTests`
/// (in `ClearskyAppTests`, a *unit*-test bundle hosted in-process via
/// `TEST_HOST`/`BUNDLE_LOADER`): that test hosts `PromisesView` directly inside the
/// test process's own `UIWindow` and can only measure the resulting layout (row tap
/// target frames) — there is no touch-injection tool available to it (`idb` is not
/// installed, `xcrun simctl` has no tap/gesture command, and `UIAccessibility`'s tree
/// is never materialized without a real assistive-technology client attached; see the
/// findings in `clearsky-ios-build-conventions` project memory), so it cannot simulate
/// a real finger tap or prove `.onTapGesture`'s closure actually fires.
///
/// A UI test bundle (`ClearskyAppUITests`, `TEST_TARGET_NAME: ClearskyApp` in
/// `project.yml`) is a different mechanism entirely: it launches `ClearskyApp` as its
/// own real, separate process in the simulator and drives it externally through the
/// OS's UI-testing driver (`XCUIApplication`/`XCUIElement.tap()`), the same mechanism
/// Xcode's own UI test recorder uses — a real synthetic touch event delivered to the
/// running app, not an in-process introspection trick. This is genuinely possible here
/// in a way none of the in-process approaches were.
///
/// Hermetic by construction: `PromiseStore` persists to a real file
/// (`~/Documents/promises.json`) inside the app's own sandbox container, which
/// survives across separate app launches on the same simulator — including between
/// unrelated manual checks and previous runs of this very test. Rather than assume
/// any pre-existing data (fragile, and untrue on a genuinely fresh install — see
/// `ClearskyApp.swift`'s `makePromiseStore()` doc comment: the Promises list renders
/// its `emptyState` when `store.promises.isEmpty`, so nothing guarantees a row exists
/// without this), this test:
/// 1. Launches with `--uitest-reset-promises`, which `ClearskyApp.swift` checks for
///    and deletes any persisted `promises.json` before `PromiseStore` reads it.
/// 2. Drives the real "+" > New promise flow (`RootView`'s toolbar button,
///    `NewPromiseView`'s form) to create exactly one promise, through the same UI a
///    person would use — this is itself extra, real proof that flow works too.
/// 3. Taps the Promises tab, taps that promise's row (found by the
///    `"promiseRow-<id>"` accessibility identifier `PromisesView.row(for:)` sets),
///    and asserts the detail screen that appears shows the *exact* person name this
///    test typed in step 2 — not just "some back button appeared" (which a
///    differently-broken navigation could also produce), but the specific promise's
///    own content, which only renders if `.navigationDestination(item:
///    $selectedPromise)` really pushed `PromiseDetailView(promise:)` for the promise
///    that was actually tapped.
@MainActor
final class PromiseDetailNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    /// Unique per test run so this assertion can never accidentally pass against a
    /// leftover promise from an earlier run that, for whatever reason, survived the
    /// `--uitest-reset-promises` wipe (e.g. a future test added to this same file
    /// that doesn't reset first).
    private let personName = "UITest Jordan \(UUID().uuidString.prefix(8))"
    private let whatWasPromised = "Send the invoice by Friday"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-promises"]
        app.launch()

        let tabBar = app.tabBars.element
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar did not appear after launch")
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testTappingPromiseRowNavigatesToDetailView() {
        createPromiseThroughRealUI(personName: personName, whatWasPromised: whatWasPromised)

        // Step 1: Navigate to the Promises tab.
        let tabBar = app.tabBars.element
        let promisesTab = tabBar.buttons["Promises"]
        XCTAssertTrue(promisesTab.exists, "Promises tab button does not exist in tab bar")
        promisesTab.tap()

        // `PromisesView`'s headline renders through `.displayHeadlineStyle()`
        // (`DesignTokens.swift`), which applies `.textCase(.uppercase)` — SwiftUI's
        // `Text` derives its accessibility label from the rendered string, so the
        // label really is "PROMISES", not "Promises". Confirmed against a real
        // accessibility-hierarchy dump (`app.debugDescription`) the first time this
        // test was written, before this was known.
        let promisesTitle = app.staticTexts["PROMISES"]
        XCTAssertTrue(
            promisesTitle.waitForExistence(timeout: 5),
            "Promises title did not appear after tapping Promises tab"
        )

        // Step 2: Find and tap the Promise row this test just created.
        // `PromisesView.row(for:)` sets `.accessibilityIdentifier("promiseRow-\(promise.id)")`
        // on the row's container view, but a real accessibility-hierarchy dump
        // (`app.debugDescription`, captured while first writing this test) showed
        // that identifier does not produce its own accessibility element — SwiftUI
        // instead applies it to every descendant accessibility element of that
        // container: the row's small `.planned` tap-to-complete circle `Button` AND
        // its three `StaticText`s (person name, due date, what-was-promised) all
        // carry it. Tapping the circle specifically would be wrong here — per
        // `clearsky-ios-build-conventions` project memory, "a nested Button's own tap
        // gesture takes precedence over an ancestor's plain `.onTapGesture`", so that
        // circle has its own action (marking the promise kept), not this row's
        // navigation. Tapping the `whatWasPromised` `StaticText` instead — a plain,
        // non-Button descendant, fully inside the row's `.contentShape(Rectangle())`
        // — reliably falls through to the row's own `.onTapGesture` that sets
        // `selectedPromise`.
        let promiseRowText = app.staticTexts[whatWasPromised]
        XCTAssertTrue(
            promiseRowText.waitForExistence(timeout: 5),
            "No Promise row rendered after creating one through the real + > New promise flow"
        )
        promiseRowText.tap()

        // Step 3: Verify the real navigation fired — the detail screen for THIS
        // promise (identified by the exact person name typed above, which only this
        // one promise has) is now on screen, and the Promises list title is gone.
        // `PromiseDetailView.header` also applies `.displayHeadlineStyle()` to the
        // person name `Text`, but — confirmed via a real accessibility-hierarchy dump
        // — unlike the `Text("Promises")` string-literal title above, a `Text`
        // initialized from a `String` variable (`Text(promise.personName)`) keeps its
        // original-case accessibility label even under `.textCase(.uppercase)`; only
        // the on-screen glyphs render uppercase. So this query intentionally does NOT
        // uppercase `personName`, unlike the "PROMISES" title query above.
        let detailPersonName = app.staticTexts[personName]
        XCTAssertTrue(
            detailPersonName.waitForExistence(timeout: 3),
            "PromiseDetailView's person name did not appear after tapping the Promise row " +
            "— the tap either did not set `selectedPromise` or `.navigationDestination(item:)` " +
            "did not push PromiseDetailView"
        )

        XCTAssertFalse(
            promisesTitle.exists,
            "Promises list title still visible; detail view may not have navigated"
        )

        // A NavigationStack push always installs a system back button in the nav bar.
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(
            backButton.exists,
            "No back button in the navigation bar after the push; not a real NavigationStack push"
        )

        // Attach a real screenshot of the pushed detail screen as PR/proof evidence —
        // `.keepAlways` so it survives in the `.xcresult` bundle even though this test
        // passed (Xcode's default only keeps attachments from a *failure*).
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "PromiseDetailView-after-row-tap"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        print("\u{2713} Promise row tap navigated to PromiseDetailView for \"\(personName)\"")
    }

    /// Drives `RootView`'s "+" toolbar button through `NewPromiseView`'s real form to
    /// create one hand-entered promise, exactly as a person would. Runs from whichever
    /// tab is currently selected (the toolbar's "+" is shared by Today and Promises,
    /// wired once in `RootView.toolbarContent`).
    private func createPromiseThroughRealUI(personName: String, whatWasPromised: String) {
        let addButton = app.buttons["New promise"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "'+' New promise toolbar button not found")
        addButton.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Name field did not appear on New promise screen")
        nameField.tap()
        nameField.typeText(personName)

        // The "WHAT WAS SAID" field is a plain TextEditor with no placeholder text,
        // so it can't be found by label the way the "Name" TextField can — it's the
        // only UITextView on this screen.
        let whatWasSaidEditor = app.textViews.element(boundBy: 0)
        XCTAssertTrue(whatWasSaidEditor.waitForExistence(timeout: 5), "'What was said' text editor did not appear")
        whatWasSaidEditor.tap()
        whatWasSaidEditor.typeText(whatWasPromised)

        // `.today` is pre-selected by `NewPromiseView.init`, and the "Protect this
        // time" toggle defaults off — no calendar-access prompt to handle, both left
        // exactly as the form's own defaults so this only exercises the minimum
        // needed to satisfy `isSaveEnabled` (non-empty name and what-was-said).
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.exists, "Save button not found")
        XCTAssertTrue(saveButton.isEnabled, "Save button should be enabled once both required fields are filled")
        saveButton.tap()

        // NewPromiseView.save() calls dismiss(); confirm the sheet is gone and the
        // tab shell is back before continuing.
        XCTAssertTrue(
            app.tabBars.element.waitForExistence(timeout: 5),
            "Tab bar not visible again after saving a new promise — sheet may not have dismissed"
        )
    }
}
