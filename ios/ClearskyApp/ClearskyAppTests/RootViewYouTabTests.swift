import XCTest
import SwiftUI
import ClearskyCore
@testable import ClearskyApp

/// Proves the "You" tab this task adds to `RootView` is really wired into the running
/// app's tab bar — not just that the new code compiles — using the same hosted-
/// `UIWindow`/`UIHostingController` technique `RootRouterViewTests.swift` established
/// for exactly this kind of "does the real view tree contain X" question (no
/// ViewInspector/XCUITest dependency exists in this codebase; see that file's own
/// type-level doc comment and the `clearsky-ios-build-conventions` agent memory for why).
///
/// ## What this proves
///
/// `RootView`'s `TabView` bridges to a real `UITabBar` (confirmed by
/// `RootRouterViewTests`), so hosting `RootView` and reading that real, on-screen
/// `UITabBar`'s `items` is a structural fact about what actually renders, not a guess:
/// these tests assert there are really 4 items now (previously 3), and that the 4th
/// one's real title is "You" — the literal `UITabBarItem.title` SwiftUI set from this
/// task's `Label("You", systemImage: "person.crop.circle")`.
///
/// ## What was tried for "actually reachable" and empirically does NOT work here
///
/// A first version of this file also tried driving the real, embedded
/// `UITabBarController`'s `selectedIndex` directly (a standard, public, non-private
/// UIKit API — not touch injection) to index 3, then checking for a real `UISwitch`
/// appearing (`YouView`'s two `Toggle`s — Morning summary, Protect evenings — are the
/// only `Toggle`s anywhere across `TodayView`/`PromisesView`/`TriageView`, confirmed via
/// `grep -rn "Toggle(" ios/ClearskyApp/ClearskyApp/{Today,Promises,Triage}View.swift`
/// returning nothing for the other three, so a `UISwitch` would have been a genuine,
/// unique signal that `YouView`'s real `body` evaluated). That assertion failed on a
/// real device run: setting `UITabBarController.selectedIndex` directly does not
/// propagate back into SwiftUI's own `@State private var selectedTab` binding in this
/// environment/SwiftUI version, so `YouView` never actually renders this way — a real,
/// reproducible empirical finding (not flakiness; failed the same way on inspection),
/// consistent with this codebase's existing "no touch-injection tool, no
/// `accessibilityActivate()` bridge either" findings in the `clearsky-ios-build-
/// conventions` agent memory. That attempt was removed rather than left in as a
/// misleadingly-named passing test, per this codebase's "don't add a test proving
/// nothing" standard — see the same memory's mutation-testing sanity-check note.
///
/// So: this file proves the tab exists, is titled correctly, and is the 4th of 4 real
/// tab bar items. It does **not** prove that selecting it — by any means available in
/// this XCTest environment — actually renders `YouView`. That last link (does tapping
/// the real tab bar item on a real device/Simulator show the You screen) needs a manual
/// Simulator look; see this PR's description for exactly that.
@MainActor
final class RootViewYouTabTests: XCTestCase {
    private var window: UIWindow!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("duck-test-root-view-you-tab-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        super.tearDown()
    }

    /// Hosts `view` in a real `UIWindow`/`UIHostingController`, makes it key and
    /// visible, and forces a real layout pass — the same technique
    /// `RootRouterViewTests.swift`/`PromisesViewNavigationTests.swift` established for
    /// this codebase.
    @discardableResult
    private func host<V: View>(_ view: V) -> UIHostingController<V> {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        self.window = window
        return controller
    }

    /// Pumps the run loop in short bursts for up to `seconds` — same fixed-duration
    /// technique `RootRouterViewTests.swift`'s own `pump(_:)` uses, giving SwiftUI's
    /// tab-bar/switch bridging time to materialize after a layout pass or a selection
    /// change.
    private func pump(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func containsTabBar(_ view: UIView) -> Bool {
        if view is UITabBar { return true }
        for subview in view.subviews where containsTabBar(subview) {
            return true
        }
        return false
    }

    private func findTabBarController(in viewController: UIViewController) -> UITabBarController? {
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        for child in viewController.children {
            if let found = findTabBarController(in: child) {
                return found
            }
        }
        return nil
    }

    private func makeRootViewDependencies() -> (PromiseStore, SharedDraftStoreObserver) {
        let promiseStore = PromiseStore(fileURL: fileURL)
        let suiteName = "duck-test-root-view-you-tab-drafts-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let draftsObserver = SharedDraftStoreObserver(
            store: SharedDraftStore(defaults: defaults),
            defaults: defaults
        )
        return (promiseStore, draftsObserver)
    }

    // MARK: - Layer 1: the real tab bar has 4 items, the 4th titled "You"

    func testTabBarHasFourItemsWithYouLast() {
        let (promiseStore, draftsObserver) = makeRootViewDependencies()
        let view = RootView(
            promiseStore: promiseStore,
            draftsObserver: draftsObserver,
            calendarService: MockCalendarService()
        )
        let controller = host(view)
        pump(0.5)

        guard let tabBarController = findTabBarController(in: controller) else {
            XCTFail("Expected RootView's TabView to embed a real UITabBarController")
            return
        }

        let items = tabBarController.tabBar.items
        XCTAssertEqual(items?.count, 4, "Today, Promises, Triage, You")
        XCTAssertEqual(items?.map(\.title), ["Today", "Promises", "Triage", "You"])
    }

    func testTabBarStillBridgesToARealUITabBar() {
        // Belt-and-suspenders companion to RootRouterViewTests' own equivalent
        // assertion on the 3-tab shape — re-confirmed here on the 4-tab shape this
        // task produces, using the same UIView-subtree search (rather than only the
        // UITabBarController-based checks above) in case a future change swaps how
        // the tab bar controller is embedded.
        let (promiseStore, draftsObserver) = makeRootViewDependencies()
        let view = RootView(
            promiseStore: promiseStore,
            draftsObserver: draftsObserver,
            calendarService: MockCalendarService()
        )
        let controller = host(view)
        pump(0.5)

        XCTAssertTrue(containsTabBar(controller.view))
    }
}
