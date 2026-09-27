import XCTest

/// Real XCUITest proving `PaywallView` and `PlansView` are genuinely reachable from the
/// running app — both screens landed additive-only in PR #34 (real StoreKit 2 pricing
/// against `Clearsky.storekit`) with no navigation wired to either; this is the "wire
/// them up" task's own proof, the same kind `PromiseDetailNavigationUITests` provides for
/// `PromiseDetailView` — see that file's type-level doc for why an XCUITest (a real,
/// separate-process synthetic touch via `XCUIApplication`/`XCUIElement.tap()`) is the
/// only mechanism in this environment that can actually simulate a finger tap, as
/// opposed to an in-process unit test hosting a view and only measuring layout.
///
/// Drives the real flow end to end: tap the "You" tab, tap the real "Plan" row
/// (`YouView.planSection`, now a `NavigationLink` to `PaywallView` instead of the inert
/// placeholder it used to be), confirm `PaywallView` is genuinely on screen, tap its
/// real "See plans" action, and confirm `PlansView` is genuinely on screen too — proving
/// both screens in one pass, matching Flow E "Trial to paid": "Paywall → plans → start
/// trial → Today." (`PaywallView`'s own type-level doc explains why "See plans" pushing
/// into `PlansView`, rather than the other way around, is the intended relationship.)
///
/// No `PromiseStore`/`SharedDraftStore` state is exercised by this flow, so only
/// `--uitest-skip-first-run` is strictly required to reach the tab bar on a genuinely
/// fresh simulator — `--uitest-reset-promises` is included anyway to match
/// `PromiseDetailNavigationUITests`' launch arguments exactly, in case a future addition
/// to this file ever touches promise data.
@MainActor
final class PaywallPlansNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-promises", "--uitest-skip-first-run"]
        app.launch()

        let tabBar = app.tabBars.element
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar did not appear after launch")
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    func testTappingPlanRowNavigatesToPaywallThenPlans() {
        // Step 1: Navigate to the "You" tab.
        let tabBar = app.tabBars.element
        let youTab = tabBar.buttons["You"]
        XCTAssertTrue(youTab.exists, "You tab button does not exist in tab bar")
        youTab.tap()

        // `YouView`'s headline renders through `.displayHeadlineStyle()`
        // (`DesignTokens.swift`), which applies `.textCase(.uppercase)` — a `Text`
        // built from a string literal (`Text("You")`) derives its accessibility label
        // from the uppercased rendered string, "YOU" — confirmed against the same
        // convention `PromiseDetailNavigationUITests` already documents for
        // `Text("Promises")` -> "PROMISES".
        let youTitle = app.staticTexts["YOU"]
        XCTAssertTrue(youTitle.waitForExistence(timeout: 5), "You screen title did not appear after tapping You tab")

        // Step 2: Tap the real "Plan" row. `YouView.planSection` renders it via
        // `YouNavigationRow`, whose title `Text` is built from the plan's own
        // `PricingPlan.yearly.displayPrice`/`.period` values ("$49.99 a year") — a
        // plain (non-uppercased) `Text(someStringExpression)`, so its accessibility
        // label matches the on-screen string exactly. Tapping the title `StaticText`
        // itself (rather than trying to hit-test the wrapping `NavigationLink`
        // directly) mirrors `PromiseDetailNavigationUITests`' own
        // `promiseRowText.tap()` precedent for a reliable, unambiguous tap target.
        let planRowTitle = app.staticTexts["$49.99 a year"]
        XCTAssertTrue(planRowTitle.waitForExistence(timeout: 5), "Plan row did not render on the You screen")
        planRowTitle.tap()

        // Step 3: Verify PaywallView is genuinely on screen. Its headline
        // (`Text("Everything included")`, also under `.displayHeadlineStyle()`) becomes
        // "EVERYTHING INCLUDED" for the same reason as "YOU"/"PROMISES" above.
        let paywallTitle = app.staticTexts["EVERYTHING INCLUDED"]
        XCTAssertTrue(
            paywallTitle.waitForExistence(timeout: 5),
            "PaywallView's headline did not appear after tapping the Plan row — the tap either " +
            "did not fire, or YouView.planSection's NavigationLink is not wired to PaywallView"
        )

        // "THE TRIAL, HONESTLY" is a hardcoded-uppercase string literal
        // (`Text("THE TRIAL, HONESTLY")` in `PaywallView.timeline`, no `.textCase`
        // needed since the literal is already uppercase) unique to `PaywallView` —
        // confirmed absent from `YouView.swift`/`PlansView.swift` via
        // `grep -rn "THE TRIAL, HONESTLY"`. Distinguishes "really pushed to Paywall"
        // from a false positive on the headline alone.
        let trialHonestlyLabel = app.staticTexts["THE TRIAL, HONESTLY"]
        XCTAssertTrue(
            trialHonestlyLabel.waitForExistence(timeout: 3),
            "PaywallView's trial timeline section did not appear"
        )

        XCTAssertFalse(youTitle.exists, "You screen title still visible; Paywall may not have navigated")

        let paywallBackButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(
            paywallBackButton.exists,
            "No back button in the navigation bar after pushing Paywall; not a real NavigationStack push"
        )

        let paywallScreenshot = XCTAttachment(screenshot: app.screenshot())
        paywallScreenshot.name = "PaywallView-after-plan-row-tap"
        paywallScreenshot.lifetime = .keepAlways
        add(paywallScreenshot)

        // Step 4: Tap PaywallView's real "See plans" action.
        // `PaywallView.primaryButton` is a `NavigationLink` whose label is a single
        // `Text("See plans")` with no sibling elements (unlike `YouNavigationRow`,
        // which has a title, a subtitle and a chevron image as separate children and
        // so exposes its title as its own `StaticText`) — SwiftUI collapses a
        // single-child label like this into one accessibility element carrying the
        // `.button` trait, so it is queried via `app.buttons`, not
        // `app.staticTexts` — confirmed empirically: the equivalent `staticTexts`
        // query found nothing here even after the standard wait.
        let seePlansButton = app.buttons["See plans"]
        XCTAssertTrue(seePlansButton.waitForExistence(timeout: 5), "PaywallView's 'See plans' action did not appear")
        seePlansButton.tap()

        // Step 5: Verify PlansView is genuinely on screen.
        // `Text("Choose how to pay.")` in `PlansView.body` is a plain, non-uppercased
        // subtitle unique to this screen — confirmed absent from `PaywallView.swift`/
        // `YouView.swift` via `grep -rn "Choose how to pay"`. Distinguishes "really
        // pushed to Plans" from `PlansView`'s own headline (`Text("Plans")` ->
        // "PLANS") alone, the same "don't rely on a single, reusable-sounding string"
        // discipline `PromiseDetailNavigationUITests` documents for its own
        // person-name-alone pitfall.
        let choosePayLabel = app.staticTexts["Choose how to pay."]
        XCTAssertTrue(
            choosePayLabel.waitForExistence(timeout: 5),
            "PlansView's 'Choose how to pay.' subtitle did not appear after tapping 'See plans' — the tap " +
            "either did not fire, or PaywallView.primaryButton's NavigationLink is not wired to PlansView"
        )

        XCTAssertFalse(trialHonestlyLabel.exists, "Paywall's trial timeline still visible; Plans may not have navigated")

        // A second, distinct NavigationStack push installs its own back button.
        let plansBackButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(
            plansBackButton.exists,
            "No back button in the navigation bar after pushing Plans; not a real NavigationStack push"
        )

        let plansScreenshot = XCTAttachment(screenshot: app.screenshot())
        plansScreenshot.name = "PlansView-after-see-plans-tap"
        plansScreenshot.lifetime = .keepAlways
        add(plansScreenshot)

        print("\u{2713} Plan row tap navigated to PaywallView, and 'See plans' navigated to PlansView")
    }
}
