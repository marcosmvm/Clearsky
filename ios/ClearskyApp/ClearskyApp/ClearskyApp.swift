import SwiftUI

@main
struct ClearskyApp: App {
    /// The one shared `PromiseStore` for the whole app — persists to
    /// `~/Documents/promises.json` (see `PromiseStore.defaultFileURL`). `@StateObject`
    /// so it survives view identity changes and SwiftUI owns its lifetime for the
    /// life of the app.
    @StateObject private var promiseStore = ClearskyApp.makePromiseStore()

    /// Builds the app's real `PromiseStore`, first deleting any persisted
    /// `~/Documents/promises.json` when launched with `--uitest-reset-promises` —
    /// `PromiseDetailNavigationUITests` (`ClearskyAppUITests`) passes this so a real,
    /// separate-process UI test run always starts from an empty Promises list
    /// regardless of what a prior manual check or test run left on this simulator's
    /// shared `com.marcosmvm.clearsky.app` container, then creates its own promise
    /// through the real "+" > New promise flow before asserting on tap-through
    /// navigation. Gated behind this exact, never-set-outside-tests argument so
    /// production launches (and every other scheme/target) are unaffected. Must run
    /// as this stored property's own initializer expression, not inside `init()`'s
    /// body below — a stored property's default-value expression is evaluated before
    /// any explicit `init()` statement executes, and `PromiseStore.init` already
    /// reads the file the moment it is constructed, so deleting it any later would be
    /// too late.
    @MainActor
    private static func makePromiseStore() -> PromiseStore {
        if ProcessInfo.processInfo.arguments.contains("--uitest-reset-promises") {
            try? FileManager.default.removeItem(at: PromiseStore.defaultFileURL)
        }
        return PromiseStore()
    }

    /// Forces `hasCompletedFirstRun` (below) to `true` in the real `UserDefaults.standard`
    /// when launched with `--uitest-skip-first-run` — `PromiseDetailNavigationUITests`
    /// (`ClearskyAppUITests`) passes this so a genuinely fresh install (no prior
    /// `UserDefaults` state at all, e.g. a brand-new simulator that has never run this app)
    /// lands straight on `RootView`'s tab bar instead of `RootRouterView` first routing
    /// through `FirstRunFlowView`'s onboarding sequence, which has no tab bar for a test
    /// to find. Added since PR #31 ("First run flow") introduced that routing after this
    /// test's original `--uitest-reset-promises` hook was written — that hook only ever
    /// reset promise data, so it left first-run state untouched on a clean install.
    ///
    /// Deliberately its own dedicated flag rather than folded into
    /// `--uitest-reset-promises`: the two hooks reset unrelated state (promise data vs.
    /// first-run routing), and a future UI test that wants a fresh Promises list while
    /// still exercising the real first-run flow needs to be able to pass one without the
    /// other.
    ///
    /// Declared as its own instance property (assigned from this static function, same
    /// shape as `promiseStore` immediately above) so it runs as a stored property's
    /// default-value expression, evaluated in declaration order before `init()`'s body —
    /// same timing rule `makePromiseStore()`'s own doc comment already establishes. In
    /// practice `@AppStorage` (unlike `PromiseStore`) reads `UserDefaults` live on every
    /// access rather than caching a value once at construction, so this would still work
    /// declared after `hasCompletedFirstRun` too — kept above it anyway to match the
    /// established convention and make the "runs first" intent obvious to a future reader.
    @MainActor
    private static func applyUITestFirstRunOverrideIfNeeded() {
        if ProcessInfo.processInfo.arguments.contains("--uitest-skip-first-run") {
            UserDefaults.standard.set(true, forKey: FirstRunDefaultsKey.hasCompletedFirstRun)
        }
    }

    /// Triggers `applyUITestFirstRunOverrideIfNeeded()` at instance-property-init time —
    /// see that function's doc comment. The `Void` value itself is never read; this
    /// property exists only for its default-value expression's side effect.
    @MainActor
    private let uitestFirstRunOverride: Void = ClearskyApp.applyUITestFirstRunOverrideIfNeeded()

    /// Live view of the App Group inbox the Share Extension appends captured drafts
    /// to. Wraps a `SharedDraftStore` backed by the real App Group suite in production
    /// (falling back to `.standard` only if the group container is unavailable — e.g.
    /// a build without the entitlement applied — so the app never crashes on launch
    /// over this), and re-reads that store every time its `UserDefaults` reports a
    /// change, so `RootView`'s badge and `TodayView`'s primary card stay live without
    /// a manual refresh — see `SharedDraftStoreObserver`.
    @StateObject private var draftsObserver: SharedDraftStoreObserver

    /// The real, `EKEventStore`-backed `CalendarHolding` conformer. Typed as the
    /// protocol (not the concrete type) at every call site downstream so a preview or
    /// a test can substitute `MockCalendarService`/a fake instead.
    private let calendarService: CalendarHolding = EventKitCalendarService()

    /// The real, `UNUserNotificationCenter`-backed `NotificationPermissionRequesting`
    /// conformer, mirroring `calendarService` immediately above — typed as the
    /// protocol so `FirstRunFlowView` (the one call site that uses it) can be handed a
    /// mock/no-op conformer in a preview or a test instead.
    private let notificationPermissionService: NotificationPermissionRequesting = SystemNotificationPermissionService()

    /// Whether this install has ever completed first run (connect calendar, then
    /// notification permission — see `FirstRunFlowView`'s own doc comment for why
    /// Sign-in and Inner circle are not part of that sequence yet). `false` on a brand
    /// new install; flipped to `true` exactly once, by `RootRouterView`'s
    /// `onFirstRunFinished` closure below, and never flipped back.
    @AppStorage(FirstRunDefaultsKey.hasCompletedFirstRun) private var hasCompletedFirstRun = false

    /// Explicit `init()` only because `draftsObserver` needs the same `UserDefaults`
    /// instance passed to both the `SharedDraftStore` it wraps and its own
    /// notification subscription (see `SharedDraftStoreObserver.init`) — a single
    /// property-initializer expression can't build both from one shared local. Every
    /// other property keeps its own default-value initializer as before.
    init() {
        let defaults = UserDefaults(suiteName: SharedDraftStore.appGroupIdentifier) ?? .standard
        _draftsObserver = StateObject(
            wrappedValue: SharedDraftStoreObserver(store: SharedDraftStore(defaults: defaults), defaults: defaults)
        )
    }

    /// A thin wrapper around `RootRouterView` — see that type's own doc comment for why
    /// the actual `hasCompletedFirstRun` branch lives there instead of inline here: an
    /// `App`/`Scene` can't be hosted in an XCTest, only a `View` can, so the branch
    /// itself needs to live on a plain `View` to be testable at all.
    var body: some Scene {
        WindowGroup {
            RootRouterView(
                hasCompletedFirstRun: hasCompletedFirstRun,
                promiseStore: promiseStore,
                draftsObserver: draftsObserver,
                calendarService: calendarService,
                notificationPermissionService: notificationPermissionService,
                onFirstRunFinished: { hasCompletedFirstRun = true }
            )
        }
    }
}
