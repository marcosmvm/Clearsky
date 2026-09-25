import Foundation
import Combine
import ClearskyCore

/// Makes `Shared/SharedDraftStore.swift`'s `UserDefaults`-backed inbox live for
/// SwiftUI, app-side only.
///
/// `SharedDraftStore` is a deliberately plain, Combine-free struct (see its own doc
/// comment) because it is compiled into both `ClearskyApp` and
/// `ClearskyShareExtension` — the extension has no reason to carry an `ObservableObject`
/// dependency, so that file must not change. Before this type existed, `RootView`'s
/// toolbar badge and `TodayView`'s primary card each called `sharedDraftStore.loadAll()`
/// directly from a computed property — a call that only happened to look fresh when
/// SwiftUI re-rendered the view for some unrelated reason. Nothing actually observed
/// the store, so a draft the Share Extension appended while the app was open (e.g. the
/// person briefly backgrounds the app to share, then returns to it) did not reliably
/// show up until something else forced a re-render.
///
/// This class is the app-only wrapper that closes that gap: it holds one
/// `SharedDraftStore`, exposes its contents as `@Published var drafts`, and re-runs
/// `loadAll()` every time `UserDefaults.didChangeNotification` fires for the specific
/// `UserDefaults` instance the store was built over. That notification is Apple's
/// documented mechanism for observing a `UserDefaults` instance's contents changing,
/// including an externally-written change (from another process sharing the same App
/// Group suite, i.e. the Share Extension) that `UserDefaults` picks up and reports the
/// next time the app is foregrounded — exactly the moment this bug shows up. A caller
/// that holds this object instead of a raw `SharedDraftStore` never needs to call a
/// manual `refresh()`: `drafts` (and anything derived from it, like `count`) recomputes
/// on its own the instant the underlying store changes.
///
/// `@MainActor` for the same reason `PromiseStore` is: `@Published` state drives
/// SwiftUI view updates directly, so every mutation of it must happen on the main
/// actor.
@MainActor
final class SharedDraftStoreObserver: ObservableObject {
    @Published private(set) var drafts: [CapturedPromiseDraft]

    private let store: SharedDraftStore
    private var cancellable: AnyCancellable?

    /// - Parameters:
    ///   - store: The `SharedDraftStore` to observe. Its `append`/`remove`/`clear`
    ///     methods stay the source of truth for actually mutating the inbox — this
    ///     class wraps `remove(id:)` (the one call sites in this target need) so a
    ///     caller can hold this object alone instead of a `SharedDraftStore` plus this
    ///     observer side by side.
    ///   - defaults: The exact `UserDefaults` instance `store` was constructed with.
    ///     Passed separately, rather than reached from inside `store` (whose
    ///     `defaults` property is private), so the `NotificationCenter` subscription
    ///     below can be scoped to that one instance rather than every `UserDefaults`
    ///     in the process.
    init(store: SharedDraftStore, defaults: UserDefaults) {
        self.store = store
        self.drafts = store.loadAll()

        cancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reload()
            }
    }

    /// Convenience for the toolbar badge (`RootView`) so it doesn't need to spell out
    /// `drafts.count` itself.
    var count: Int { drafts.count }

    /// Removes one draft by id — e.g. once the confirm/edit screen has resolved it —
    /// and reloads `drafts` immediately rather than waiting on the notification round
    /// trip, so the caller's own write is reflected without delay even before
    /// `UserDefaults.didChangeNotification` has a chance to fire.
    func remove(id: String) {
        store.remove(id: id)
        reload()
    }

    private func reload() {
        drafts = store.loadAll()
    }
}
