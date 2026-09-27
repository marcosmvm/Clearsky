import SwiftUI

@main
struct ClearskyApp: App {
    /// The one shared `PromiseStore` for the whole app — persists to
    /// `~/Documents/promises.json` (see `PromiseStore.defaultFileURL`). `@StateObject`
    /// so it survives view identity changes and SwiftUI owns its lifetime for the
    /// life of the app.
    @StateObject private var promiseStore = PromiseStore()

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
    /// new install; flipped to `true` exactly once, by `FirstRunFlowView`'s own
    /// `onFinished` closure below, and never flipped back.
    @AppStorage("hasCompletedFirstRun") private var hasCompletedFirstRun = false

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

    var body: some Scene {
        WindowGroup {
            if hasCompletedFirstRun {
                RootView(
                    promiseStore: promiseStore,
                    draftsObserver: draftsObserver,
                    calendarService: calendarService
                )
            } else {
                FirstRunFlowView(
                    calendarService: calendarService,
                    notificationPermissionService: notificationPermissionService,
                    onFinished: { hasCompletedFirstRun = true }
                )
            }
        }
    }
}
