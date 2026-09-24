import XCTest
@testable import ClearskyCore

final class NotificationBudgetTests: XCTestCase {

    // MARK: - Fixtures

    /// A fixed, non-system-default time zone so these tests never depend on the
    /// machine running them.
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar
    }

    /// Builds an exact local `Date` from calendar components, so tests never rely
    /// on `Date()` "today" for determinism.
    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = pacific
        return calendar.date(from: components)!
    }

    // MARK: - NotificationCategory

    func testExactlyThreeCategoriesExist() {
        XCTAssertEqual(NotificationCategory.allCases.count, 3)
        XCTAssertEqual(
            Set(NotificationCategory.allCases),
            [.morningSummary, .duePromiseReminder, .sundayRecap]
        )
    }

    // MARK: - NotificationIdempotency

    func testIdempotencyKeyIsStableForIdenticalInputs() {
        let day = date(year: 2026, month: 9, day: 24)
        let keyA = NotificationIdempotency.key(
            category: .duePromiseReminder,
            userID: "user-1",
            objectID: "promise-1",
            date: day,
            timeZone: pacific
        )
        let keyB = NotificationIdempotency.key(
            category: .duePromiseReminder,
            userID: "user-1",
            objectID: "promise-1",
            date: day,
            timeZone: pacific
        )
        XCTAssertEqual(keyA, keyB)
    }

    func testIdempotencyKeyDiffersByDate() {
        let today = date(year: 2026, month: 9, day: 24)
        let tomorrow = date(year: 2026, month: 9, day: 25)
        let keyToday = NotificationIdempotency.key(
            category: .morningSummary,
            userID: "user-1",
            objectID: nil,
            date: today,
            timeZone: pacific
        )
        let keyTomorrow = NotificationIdempotency.key(
            category: .morningSummary,
            userID: "user-1",
            objectID: nil,
            date: tomorrow,
            timeZone: pacific
        )
        XCTAssertNotEqual(keyToday, keyTomorrow)
    }

    func testIdempotencyKeyDiffersByCategory() {
        let day = date(year: 2026, month: 9, day: 24)
        let morning = NotificationIdempotency.key(
            category: .morningSummary,
            userID: "user-1",
            objectID: nil,
            date: day,
            timeZone: pacific
        )
        let recap = NotificationIdempotency.key(
            category: .sundayRecap,
            userID: "user-1",
            objectID: nil,
            date: day,
            timeZone: pacific
        )
        // Both pass a nil objectID; only the category segment differs, and that
        // must be enough to keep the keys distinct.
        XCTAssertNotEqual(morning, recap)
    }

    func testIdempotencyKeyDiffersByObjectAndUser() {
        let day = date(year: 2026, month: 9, day: 24)
        let promiseOne = NotificationIdempotency.key(
            category: .duePromiseReminder,
            userID: "user-1",
            objectID: "promise-1",
            date: day,
            timeZone: pacific
        )
        let promiseTwo = NotificationIdempotency.key(
            category: .duePromiseReminder,
            userID: "user-1",
            objectID: "promise-2",
            date: day,
            timeZone: pacific
        )
        let otherUser = NotificationIdempotency.key(
            category: .duePromiseReminder,
            userID: "user-2",
            objectID: "promise-1",
            date: day,
            timeZone: pacific
        )
        XCTAssertNotEqual(promiseOne, promiseTwo)
        XCTAssertNotEqual(promiseOne, otherUser)
    }

    // MARK: - NotificationBudget: morning summary

    func testMorningSummaryAllowedWhenNotAlreadySentToday() {
        let today = date(year: 2026, month: 9, day: 24)
        XCTAssertTrue(
            NotificationBudget.isAllowed(
                category: .morningSummary,
                alreadySentToday: [],
                date: today,
                timeZone: pacific
            )
        )
    }

    func testMorningSummaryBlockedOnSecondAttemptSameDay() {
        let today = date(year: 2026, month: 9, day: 24)
        XCTAssertFalse(
            NotificationBudget.isAllowed(
                category: .morningSummary,
                alreadySentToday: [.morningSummary],
                date: today,
                timeZone: pacific
            )
        )
    }

    func testMorningSummaryAllowedAgainNextDay() {
        // "Already sent today" is scoped to a single day's set; the caller is
        // expected to reset it once the calendar day rolls over. This test proves
        // a fresh (empty) set on the next day is allowed again, i.e. nothing in
        // the function itself carries a cross-day block.
        let tomorrow = date(year: 2026, month: 9, day: 25)
        XCTAssertTrue(
            NotificationBudget.isAllowed(
                category: .morningSummary,
                alreadySentToday: [],
                date: tomorrow,
                timeZone: pacific
            )
        )
    }

    // MARK: - NotificationBudget: due-promise reminder

    func testDuePromiseReminderBlockedWhenNoPromiseDueToday() {
        let today = date(year: 2026, month: 9, day: 24)
        XCTAssertFalse(
            NotificationBudget.isAllowed(
                category: .duePromiseReminder,
                alreadySentToday: [],
                hasDuePromiseToday: false,
                date: today,
                timeZone: pacific
            )
        )
    }

    func testDuePromiseReminderAllowedOnceWhenAPromiseIsDue() {
        let today = date(year: 2026, month: 9, day: 24)
        XCTAssertTrue(
            NotificationBudget.isAllowed(
                category: .duePromiseReminder,
                alreadySentToday: [],
                hasDuePromiseToday: true,
                date: today,
                timeZone: pacific
            )
        )
    }

    func testDuePromiseReminderNotMultipliedByMultipleDuePromises() {
        // `hasDuePromiseToday` is a Bool, not a count, and stays true whether one
        // or several promises are due today. Once the single digest reminder has
        // sent, the same day with the same (still-true) flag must not allow a
        // second one — proving one due-promise day never yields more than one
        // reminder no matter how many promises are actually due.
        let today = date(year: 2026, month: 9, day: 24)
        XCTAssertFalse(
            NotificationBudget.isAllowed(
                category: .duePromiseReminder,
                alreadySentToday: [.duePromiseReminder],
                hasDuePromiseToday: true,
                date: today,
                timeZone: pacific
            )
        )
    }

    // MARK: - NotificationBudget: Sunday recap

    func testSundayRecapAllowedOnAKnownSunday() {
        // 2023-01-01 is a known, verified Sunday.
        let knownSunday = date(year: 2023, month: 1, day: 1)
        XCTAssertTrue(
            NotificationBudget.isAllowed(
                category: .sundayRecap,
                alreadySentToday: [],
                sundayRecapSentThisWeek: false,
                date: knownSunday,
                timeZone: pacific
            )
        )
    }

    func testSundayRecapBlockedOnAKnownNonSunday() {
        // 2023-01-02 is a known, verified Monday.
        let knownMonday = date(year: 2023, month: 1, day: 2)
        XCTAssertFalse(
            NotificationBudget.isAllowed(
                category: .sundayRecap,
                alreadySentToday: [],
                sundayRecapSentThisWeek: false,
                date: knownMonday,
                timeZone: pacific
            )
        )
    }

    func testSundayRecapBlockedWhenAlreadySentThisWeek() {
        let knownSunday = date(year: 2023, month: 1, day: 1)
        XCTAssertFalse(
            NotificationBudget.isAllowed(
                category: .sundayRecap,
                alreadySentToday: [],
                sundayRecapSentThisWeek: true,
                date: knownSunday,
                timeZone: pacific
            )
        )
    }

    // MARK: - NotificationQuietHours

    func testQuietHoursDefersInsideTheWindow() {
        // 10pm is inside the default 9pm-8am window.
        let lateNight = date(year: 2026, month: 9, day: 24, hour: 22, minute: 0)
        let decision = NotificationQuietHours.decision(for: lateNight, timeZone: pacific)
        guard case .deferUntil(let resumeAt) = decision else {
            return XCTFail("Expected .deferUntil, got \(decision)")
        }
        // Should resume at 8am the next calendar day.
        let expectedResume = date(year: 2026, month: 9, day: 25, hour: 8, minute: 0)
        XCTAssertEqual(resumeAt, expectedResume)
    }

    func testQuietHoursDefersAfterMidnightToSameDayEnd() {
        // 2am is inside the wrapped window (still before 8am end).
        let earlyMorning = date(year: 2026, month: 9, day: 25, hour: 2, minute: 0)
        let decision = NotificationQuietHours.decision(for: earlyMorning, timeZone: pacific)
        guard case .deferUntil(let resumeAt) = decision else {
            return XCTFail("Expected .deferUntil, got \(decision)")
        }
        // Should resume at 8am the same calendar day, not the next one.
        let expectedResume = date(year: 2026, month: 9, day: 25, hour: 8, minute: 0)
        XCTAssertEqual(resumeAt, expectedResume)
    }

    func testQuietHoursSendsNowOutsideTheWindow() {
        // 10am is well outside the default 9pm-8am window.
        let midMorning = date(year: 2026, month: 9, day: 24, hour: 10, minute: 0)
        XCTAssertEqual(
            NotificationQuietHours.decision(for: midMorning, timeZone: pacific),
            .sendNow
        )
    }

    func testQuietHoursWindowIsInclusiveOfStartHourAndExclusiveOfEndHour() {
        let startOfWindow = date(year: 2026, month: 9, day: 24, hour: 21, minute: 0)
        if case .sendNow = NotificationQuietHours.decision(for: startOfWindow, timeZone: pacific) {
            XCTFail("9pm exactly should already be inside the quiet window")
        }

        let endOfWindow = date(year: 2026, month: 9, day: 25, hour: 8, minute: 0)
        XCTAssertEqual(
            NotificationQuietHours.decision(for: endOfWindow, timeZone: pacific),
            .sendNow,
            "8am exactly should already be outside the quiet window"
        )
    }

    // MARK: - NotificationTapResult / stale target

    func testLiveTargetShowsTheTargetItself() {
        XCTAssertEqual(
            NotificationTapResult.resolve(targetState: .live),
            .showTarget
        )
    }

    func testStaleTargetReturnsExactFallbackCopy() {
        let result = NotificationTapResult.resolve(targetState: .stale)
        XCTAssertEqual(result, .showFallback(message: "You're all caught up here"))
        XCTAssertEqual(NotificationTapResult.staleFallbackMessage, "You're all caught up here")
    }

    // MARK: - NotificationDeliveryOutcome

    func testDeliveryOutcomeCasesMatchAuditRequiredAnalyticsSplit() {
        let expected: Set<NotificationDeliveryOutcome> = [.sent, .delivered, .opened, .suppressed, .actedOn]
        XCTAssertEqual(NotificationDeliveryOutcome.allCases.count, 5)
        XCTAssertEqual(Set(NotificationDeliveryOutcome.allCases), expected)
    }
}
