import Foundation

/// The closed set of notification categories V1 may send.
///
/// Mirrors the hard product rule in the repository root `README.md`
/// §"Interactions and behaviour" — "**One nudge a day** is a hard product
/// constraint, not a setting: a morning summary, plus a reminder only when a dated
/// promise is due, plus the Sunday recap. There is no fourth category in V1." — and
/// `CLAUDE_CODE_AUDIT.md` §"Notification budget", which requires "exactly three
/// categories: morning summary, due-promise reminder, Sunday recap." A closed enum,
/// rather than a free-form string or a feature sending directly, is what makes
/// "no fourth category" true in code: nothing outside this file can add a case, and
/// every other type below is keyed off this vocabulary rather than a string.
public enum NotificationCategory: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case morningSummary
    case duePromiseReminder
    case sundayRecap
}

/// Builds the idempotency key a notification attempt is deduplicated against.
///
/// `CLAUDE_CODE_AUDIT.md` §"Notification budget" requires "one idempotency key per
/// type/user/object/date". This is the single place that composition rule lives, so
/// a caller building a key and a caller checking one never drift apart.
///
/// **Composition rule:** `"<category rawValue>:<userID>:<objectID or "-">:<calendar
/// date as yyyy-MM-dd in the given time zone>"`.
/// - The date segment is a timezone-local calendar day, not a timestamp, so two
///   attempts to send the same notification on the same local day always collide
///   onto the same key regardless of the exact instant each attempt fires. This is
///   also the timezone-awareness the audit doc calls out: the same instant can be
///   two different calendar days depending on the user's time zone, and the key
///   must follow the user's day, not UTC or the server's day.
/// - `objectID` is the per-object identifier a notification is about — for example
///   the promise ID behind a due-promise reminder. `.morningSummary` and
///   `.sundayRecap` are not about one particular object, so callers pass `nil` for
///   those; the literal placeholder `"-"` stands in so the key always has the same
///   number of segments. The category segment still differs between
///   `.morningSummary` and `.sundayRecap`, so two categories that both pass `nil`
///   can never collide with each other.
public enum NotificationIdempotency {

    /// Returns the stable, unique idempotency key for one notification attempt.
    /// Calling this twice with identical arguments always returns the same string;
    /// changing the category, user, object or calendar date always changes it.
    public static func key(
        category: NotificationCategory,
        userID: String,
        objectID: String?,
        date: Date,
        timeZone: TimeZone,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let components = localCalendar.dateComponents([.year, .month, .day], from: date)
        let dateString = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        let object = objectID ?? "-"
        return "\(category.rawValue):\(userID):\(object):\(dateString)"
    }
}

/// The pure daily/weekly budget check every notification send must pass before it is
/// allowed to reach `UNUserNotificationCenter` (or any other transport). This type
/// makes no notification calls itself — it is the decision layer beneath that,
/// described by `CLAUDE_CODE_AUDIT.md` §"Notification budget" as "a notification
/// policy layer as the single gateway rather than letting features send directly."
public enum NotificationBudget {

    /// Returns whether `category` may send right now, given what has already sent.
    ///
    /// - `alreadySentToday`: the categories already sent for the user's current
    ///   calendar day. Callers are expected to compute this from their own send log
    ///   (or `NotificationIdempotency` keys already recorded for today), not from
    ///   this function.
    /// - `hasDuePromiseToday`: whether the user has at least one dated promise due
    ///   on `date`. `.duePromiseReminder` is allowed only when this is `true`.
    /// - `sundayRecapSentThisWeek`: whether a Sunday recap has already sent for the
    ///   week containing `date`. Unlike the other two categories, "once a day" does
    ///   not describe the recap's cap — it is once a week — so it needs its own
    ///   week-scoped signal rather than reusing `alreadySentToday`, which only knows
    ///   about the current day.
    /// - `date`, `timeZone`, `calendar`: the instant being evaluated and the
    ///   timezone/calendar to resolve it against. `.sundayRecap` needs these to
    ///   decide whether `date` falls on a Sunday in the *user's* local time, not
    ///   the server's or UTC's — the same instant can be a Saturday night in one
    ///   zone and Sunday morning in another.
    ///
    /// Rules enforced, each following directly from `CLAUDE_CODE_AUDIT.md`
    /// §"Notification budget" and the README's "One nudge a day" rule:
    /// - `.morningSummary` — at most one per calendar day.
    /// - `.duePromiseReminder` — allowed only when `hasDuePromiseToday` is `true`,
    ///   and at most one per calendar day regardless of how many promises are due
    ///   that day. This is a deliberate digest choice, not an oversight: the product
    ///   rule is "a reminder", singular, "only when a dated promise is due" — it
    ///   does not say "a reminder per promise". One reminder per due promise would
    ///   turn a day with three due promises into three notifications, which blows
    ///   the "one nudge a day" budget the audit doc is checking for. Modelling the
    ///   input as a `Bool` rather than a count is what makes "not multiplied"
    ///   structurally true here: there is no count for a caller to multiply by.
    /// - `.sundayRecap` — allowed only when `Calendar` says `date` is a Sunday in
    ///   `timeZone`, and at most once per week.
    public static func isAllowed(
        category: NotificationCategory,
        alreadySentToday: Set<NotificationCategory>,
        hasDuePromiseToday: Bool = false,
        sundayRecapSentThisWeek: Bool = false,
        date: Date,
        timeZone: TimeZone,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        switch category {
        case .morningSummary:
            return !alreadySentToday.contains(.morningSummary)

        case .duePromiseReminder:
            guard hasDuePromiseToday else { return false }
            return !alreadySentToday.contains(.duePromiseReminder)

        case .sundayRecap:
            var localCalendar = calendar
            localCalendar.timeZone = timeZone
            // Gregorian calendar weekday component: 1 = Sunday ... 7 = Saturday.
            // This holds regardless of `firstWeekday`, which only affects
            // week-of-year math, not what `.weekday` reports for a given date.
            let weekday = localCalendar.component(.weekday, from: date)
            guard weekday == 1 else { return false }
            return !sundayRecapSentThisWeek
        }
    }
}

/// The result of a quiet-hours check: never a bare `Bool`, because a suppressed
/// notification must be deferred and delivered later, not silently dropped.
/// `CLAUDE_CODE_AUDIT.md` §"Notification budget" requires "quiet-hour suppression";
/// expressing it as "defer until this instant" rather than "don't send" is what
/// keeps the caller from losing the notification outright.
public enum NotificationSendDecision: Equatable, Sendable {
    /// Outside quiet hours: send immediately.
    case sendNow
    /// Inside quiet hours: hold the notification and (re)attempt it at this instant,
    /// which is quiet-hours end on the same calendar day the check was made against.
    case deferUntil(Date)
}

/// A quiet-hours window expressed as local, timezone-relative hours of the day.
/// Hour-only (no minutes) is a deliberate simplification: the audit doc calls for a
/// window, not minute-precision scheduling, and a "9pm–8am" style window is how the
/// product describes it.
public struct QuietHoursWindow: Equatable, Sendable {
    /// Local hour (0–23) quiet hours begin, inclusive.
    public let startHour: Int
    /// Local hour (0–23) quiet hours end, exclusive. May be less than `startHour`,
    /// meaning the window wraps past midnight (the default 21→8 case).
    public let endHour: Int

    public init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }

    /// The documented default: 9pm–8am local. A relationship/commitment app should
    /// not be buzzing someone overnight; this is the sane default `CLAUDE_CODE_AUDIT.md`
    /// §"Notification budget" asks for without pinning an exact window itself.
    public static let `default` = QuietHoursWindow(startHour: 21, endHour: 8)
}

/// The pure quiet-hours check every notification send must pass, alongside
/// `NotificationBudget`, before reaching any real transport.
public enum NotificationQuietHours {

    /// Returns whether `date` falls inside `window` in `timeZone`, and if so, the
    /// instant sending should resume.
    ///
    /// The deferred instant is always `window.endHour:00` local time on the
    /// earliest calendar day at or after `date` at which that instant is still in
    /// the future relative to `date` — i.e. later today if quiet-hours end hasn't
    /// passed yet today, otherwise tomorrow. For the default 9pm–8am window, a
    /// check at 11pm defers to 8am the next calendar day; a check at 2am (already
    /// inside the wrapped window) defers to 8am the same calendar day.
    public static func decision(
        for date: Date,
        timeZone: TimeZone,
        window: QuietHoursWindow = .default,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> NotificationSendDecision {
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let hour = localCalendar.component(.hour, from: date)

        let isQuiet: Bool
        if window.startHour == window.endHour {
            // Zero-width window: treat as "never quiet" rather than "always quiet",
            // since an unconfigured/degenerate window should not silently hold
            // every notification forever.
            isQuiet = false
        } else if window.startHour < window.endHour {
            isQuiet = hour >= window.startHour && hour < window.endHour
        } else {
            // Wraps past midnight, e.g. 21 -> 8.
            isQuiet = hour >= window.startHour || hour < window.endHour
        }

        guard isQuiet else { return .sendNow }

        var components = localCalendar.dateComponents([.year, .month, .day], from: date)
        components.hour = window.endHour
        components.minute = 0
        components.second = 0
        guard var deferDate = localCalendar.date(from: components) else {
            // Should be unreachable for valid inputs; fail open rather than lose
            // the notification silently.
            return .sendNow
        }
        if deferDate <= date {
            deferDate = localCalendar.date(byAdding: .day, value: 1, to: deferDate) ?? deferDate
        }
        return .deferUntil(deferDate)
    }
}

/// The analytics states a single notification attempt can be recorded against,
/// matching `CLAUDE_CODE_AUDIT.md` §"Notification budget", which requires
/// "analytics that separate sent, delivered, opened, suppressed and acted-on".
///
/// This type does not wire up real analytics plumbing — no event pipeline, no
/// logging call — it exists so a caller has one closed vocabulary to record
/// against instead of ad hoc strings that could drift out of sync with each other
/// across call sites.
public enum NotificationDeliveryOutcome: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    /// The app asked the system to deliver the notification.
    case sent
    /// The system confirms the notification reached the device.
    case delivered
    /// The user opened/tapped the notification.
    case opened
    /// `NotificationBudget` or `NotificationQuietHours` held this notification back
    /// instead of sending it.
    case suppressed
    /// The user took the notification's recommended action (for example, opened
    /// and resolved the due promise it pointed at).
    case actedOn
}

/// Whether the item a tapped notification points at is still in the state the
/// notification described, per `CLAUDE_CODE_AUDIT.md` §"Notification budget"
/// ("What happens if the target is already handled" / the stale-target fallback
/// requirement).
public enum NotificationTargetState: Equatable, Sendable {
    /// The target item is still in the state the notification was about — route to
    /// it normally.
    case live
    /// The target item was already resolved (completed, released, rescheduled,
    /// etc.) before the tap landed.
    case stale
}

/// What a notification tap should show, resolved from a `NotificationTargetState`.
///
/// `CLAUDE_CODE_AUDIT.md` §"Notification budget" requires "a stale-target fallback
/// ('You're all caught up here', never a dead route)". The fallback copy is baked in
/// here as one constant, `staleFallbackMessage`, rather than left for each call site
/// to respell — so the exact required string can only ever be produced one way.
public enum NotificationTapResult: Equatable, Sendable {
    /// Route to the real target item.
    case showTarget
    /// The target was stale; show this fallback message instead of a dead route.
    case showFallback(message: String)

    /// The exact fallback copy `CLAUDE_CODE_AUDIT.md` §"Notification budget"
    /// specifies. Always used verbatim by `resolve(targetState:)` — never
    /// paraphrased.
    public static let staleFallbackMessage = "You're all caught up here"

    /// Resolves a tap outcome from the target's current state. `.stale` always
    /// yields `staleFallbackMessage`; a tapped notification can never land on a
    /// dead route.
    public static func resolve(targetState: NotificationTargetState) -> NotificationTapResult {
        switch targetState {
        case .live:
            return .showTarget
        case .stale:
            return .showFallback(message: staleFallbackMessage)
        }
    }
}
