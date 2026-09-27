import Foundation

/// The exact `UserDefaults` key strings the first-run flow's `@AppStorage`
/// properties read and write, named once here rather than as bare string literals
/// scattered across `FirstRunFlowView.swift` and `ClearskyApp.swift`.
///
/// `calendarConnected` in particular is also read by a different, parallel task
/// this shift — the "You" screen's own `YouViewDefaultsKey.calendarConnected`
/// (`YouView.swift`, PR #32) — and `hasCompletedFirstRun`/`notificationsGranted`
/// are each a plausible dependency for a future screen. Two independently-typed
/// literals only interoperate as long as both spell the key identically; a shared
/// constant on each side turns a future rename from a silent runtime drift into a
/// compile error on whichever side didn't update. `FirstRunDefaultsKeyTests`
/// (in `FirstRunFlowViewTests.swift`) pins all three literal values so a rename
/// here is caught immediately rather than discovered later as a cross-screen bug.
enum FirstRunDefaultsKey {
    /// Whether the person connected at least one calendar account during first
    /// run. Written by `FirstRunFlowView`, read by `YouView` (`YouViewDefaultsKey
    /// .calendarConnected` — a separate constant in a separate file/branch, kept
    /// in sync only by both literals matching exactly).
    static let calendarConnected = "calendarConnected"

    /// Whether notification permission ended up granted during first run.
    /// Written by `FirstRunFlowView` only, as of this task.
    static let notificationsGranted = "notificationsGranted"

    /// Whether this install has ever completed the first-run sequence. Written by
    /// `ClearskyApp`'s `onFirstRunFinished` closure, read by `ClearskyApp`/
    /// `RootRouterView` to decide which root view to show.
    static let hasCompletedFirstRun = "hasCompletedFirstRun"
}
