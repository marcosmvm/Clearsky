import SwiftUI
import ClearskyCore

/// The one branch point between a brand-new install's first-run sequence and the real
/// three-tab app shell — pulled out of `ClearskyApp.swift`'s `body` into its own,
/// separately-testable view.
///
/// Before this type existed, `ClearskyApp.body` read `@AppStorage("hasCompletedFirstRun")`
/// and branched on it inline inside `WindowGroup { ... }` — untestable, since nothing in
/// this codebase can host a `Scene`/`App` in an XCTest, only a `View`. Mutation testing
/// proved the gap: disabling that branch (forcing it to always show `RootView`, first-run
/// or not) left every existing test green, because no test exercised the branch at all.
///
/// `RootRouterView` fixes that by being a plain `View` — hostable exactly like
/// `FirstRunFlowView`/`RootView` themselves — that takes `hasCompletedFirstRun` as a
/// plain `Bool` parameter rather than reading `@AppStorage` internally. A test builds two
/// instances (one per `Bool` value) and asserts which child renders by hosting each in a
/// real `UIWindow` and inspecting its actual on-screen content, the same technique
/// `FirstRunFlowViewTests` uses for `FirstRunFlowView`'s own step transition.
/// `ClearskyApp.body` becomes a thin wrapper: it reads the real `@AppStorage` value and
/// passes it straight through, so the only thing left untested in `ClearskyApp.swift`
/// itself is the one-line `@AppStorage` read/write, which has no branch or logic of its
/// own to break.
struct RootRouterView: View {
    /// Whether this install has ever completed first run. `false` shows
    /// `FirstRunFlowView`; `true` shows `RootView`. Read once per render — this view
    /// does not persist or mutate it itself, matching `FirstRunFlowView`'s own
    /// "caller decides what happens next" shape.
    let hasCompletedFirstRun: Bool

    @ObservedObject var promiseStore: PromiseStore
    @ObservedObject var draftsObserver: SharedDraftStoreObserver
    let calendarService: CalendarHolding
    let notificationPermissionService: NotificationPermissionRequesting

    /// Called by `FirstRunFlowView`'s own `onFinished` once the notifications step
    /// resolves. The real call site (`ClearskyApp.swift`) flips its `@AppStorage`
    /// `hasCompletedFirstRun` to `true` here, which — on the next render, since
    /// `ClearskyApp.body` reads that same `@AppStorage` value and passes it back in as
    /// this view's `hasCompletedFirstRun` — switches this view over to `RootView`.
    let onFirstRunFinished: () -> Void

    var body: some View {
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
                onFinished: onFirstRunFinished
            )
        }
    }
}
