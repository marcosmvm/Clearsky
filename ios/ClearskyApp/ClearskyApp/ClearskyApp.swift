import SwiftUI

@main
struct ClearskyApp: App {
    /// The one shared `PromiseStore` for the whole app — persists to
    /// `~/Documents/promises.json` (see `PromiseStore.defaultFileURL`). `@StateObject`
    /// so it survives view identity changes and SwiftUI owns its lifetime for the
    /// life of the app.
    @StateObject private var promiseStore = PromiseStore()

    /// The App Group inbox the Share Extension appends captured drafts to. Backed by
    /// the real App Group suite in production; falls back to `.standard` only if the
    /// group container is unavailable (e.g. a build without the entitlement applied)
    /// so the app never crashes on launch over this.
    private let sharedDraftStore = SharedDraftStore(
        defaults: UserDefaults(suiteName: SharedDraftStore.appGroupIdentifier) ?? .standard
    )

    /// The real, `EKEventStore`-backed `CalendarHolding` conformer. Typed as the
    /// protocol (not the concrete type) at every call site downstream so a preview or
    /// a test can substitute `MockCalendarService`/a fake instead.
    private let calendarService: CalendarHolding = EventKitCalendarService()

    var body: some Scene {
        WindowGroup {
            RootView(
                promiseStore: promiseStore,
                sharedDraftStore: sharedDraftStore,
                calendarService: calendarService
            )
        }
    }
}
