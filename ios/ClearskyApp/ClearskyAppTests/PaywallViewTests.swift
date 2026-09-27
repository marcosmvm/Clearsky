import XCTest
import UIKit
import SwiftUI
import ClearskyCore
@testable import ClearskyApp

final class PaywallViewTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Hosts `view` in a real `UIWindow`/`UIHostingController` and forces a real
    /// layout pass — the same technique `FirstRunFlowViewTests.swift` established for
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

    // MARK: - Hosting / layout

    /// Proves `PaywallView` — including its `NavigationLink` to `PlansView`, and
    /// `PlansView`'s own real `.task { loadProducts() }` StoreKit fetch — actually
    /// constructs and lays out inside a real `UIWindow` without crashing. This does
    /// NOT prove a real tap on "See plans" pushes `PlansView`: no touch-injection tool
    /// (`idb`/`simctl` tap) is available in this environment to simulate that tap, a
    /// limitation documented repeatedly elsewhere in this codebase's own test suite —
    /// code review is the only check on the actual push happening.
    func testPaywallViewHostsAndLaysOutWithoutCrashing() {
        let controller = host(NavigationStack { PaywallView() })
        XCTAssertNotNil(controller.view)
    }

    // MARK: - TrialTimeline

    func testReminderDayIsPinnedForTheCurrentTrialLength() {
        // Pinning test, not a formula echo — this is the only assertion that would
        // catch an accidental change to `TrialTimeline.reminderLeadDays` itself; see
        // `testReminderDayStaysDerivedFromPricingPlanTrialDays` below for the
        // complementary "still computed from PricingPlan" check.
        XCTAssertEqual(TrialTimeline.reminderDay, 12)
    }

    func testReminderDayStaysDerivedFromPricingPlanTrialDays() {
        XCTAssertEqual(TrialTimeline.reminderDay, PricingPlan.trialDays - TrialTimeline.reminderLeadDays)
    }
}
