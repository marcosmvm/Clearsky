import XCTest
@testable import ClearskyCore

final class PricingPlanTests: XCTestCase {

    func testAllThreePlansExistAndNoWeeklyPlan() {
        XCTAssertEqual(PricingPlan.allCases.count, 3)
        XCTAssertEqual(Set(PricingPlan.allCases), [.yearly, .monthly, .lifetime])
    }

    func testPriceUSD() {
        XCTAssertEqual(PricingPlan.yearly.priceUSD, Decimal(string: "49.99"))
        XCTAssertEqual(PricingPlan.monthly.priceUSD, Decimal(string: "6.99"))
        XCTAssertEqual(PricingPlan.lifetime.priceUSD, Decimal(string: "129"))
    }

    func testDisplayPrice() {
        XCTAssertEqual(PricingPlan.yearly.displayPrice, "$49.99")
        XCTAssertEqual(PricingPlan.monthly.displayPrice, "$6.99")
        XCTAssertEqual(PricingPlan.lifetime.displayPrice, "$129")
    }

    func testPeriod() {
        XCTAssertEqual(PricingPlan.yearly.period, "a year")
        XCTAssertEqual(PricingPlan.monthly.period, "a month")
        XCTAssertEqual(PricingPlan.lifetime.period, "once, forever")
    }

    func testOnlyYearlyIsDefault() {
        XCTAssertTrue(PricingPlan.yearly.isDefault)
        XCTAssertFalse(PricingPlan.monthly.isDefault)
        XCTAssertFalse(PricingPlan.lifetime.isDefault)
    }

    func testTrialDaysIsFourteen() {
        XCTAssertEqual(PricingPlan.trialDays, 14)
    }
}
