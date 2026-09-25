import Foundation
import ClearskyCore

/// Read/write access to every promise the user has captured or entered by hand.
///
/// Modelled after `Shared/SharedDraftStore.swift`'s injected-destination pattern —
/// production call sites use the default Documents-directory URL this type builds in
/// `init()`, tests pass a disposable temp file URL and remove it in `tearDown` so runs
/// never see stale promises. Unlike `SharedDraftStore` (which is `UserDefaults`-backed
/// because it only ever holds a handful of not-yet-triaged drafts and is shared with
/// the Share Extension via an App Group), `PromiseStore` persists to a JSON file in the
/// app's own Documents directory: promises are the durable, potentially long-lived
/// record the rest of the app reads from, and only `ClearskyApp` itself needs to see
/// them.
///
/// `@MainActor` because `@Published var promises` drives SwiftUI view updates directly
/// — every mutation must happen on the main actor, same as any other `ObservableObject`
/// backing a screen.
@MainActor
final class PromiseStore: ObservableObject {
    @Published private(set) var promises: [Promise] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter fileURL: Where the promise list is persisted as JSON. Defaults to
    ///   `promises.json` inside the app's real Documents directory; pass a temp file
    ///   URL from a test so runs never touch a real device's Documents directory or
    ///   collide with each other.
    init(fileURL: URL = PromiseStore.defaultFileURL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.promises = Self.load(from: fileURL, decoder: decoder)
    }

    /// `~/Documents/promises.json` in the app's sandbox container. `nonisolated`
    /// because a default parameter value is evaluated in the caller's context, which
    /// is not guaranteed to be `@MainActor` — this only builds a `URL` from
    /// `FileManager`, it touches no actor-isolated state, so it is safe to call from
    /// anywhere.
    nonisolated static var defaultFileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("promises.json")
    }

    /// Appends a new promise and persists the updated list.
    func add(_ promise: Promise) {
        promises.append(promise)
        save()
    }

    /// Replaces the promise with the same `id` as `promise`, if one exists, and
    /// persists the updated list. No-op if no promise with that id is currently held.
    func update(_ promise: Promise) {
        guard let index = promises.firstIndex(where: { $0.id == promise.id }) else { return }
        promises[index] = promise
        save()
    }

    /// Moves every `.planned` promise whose `dueDate` has already passed to
    /// `.needsANewPlan`, via the pre-existing, legal `TriageStateMachine.table` row
    /// `(from: .planned, action: .dateNoLongerWorks, to: .needsANewPlan)` — nothing in
    /// the app called that row until this method. A promise in any other state, or a
    /// `.planned` promise whose `dueDate` is still `now` or later, is left untouched.
    ///
    /// Same pattern as `update(_:)`: mutate the held `promises`, then persist once.
    ///
    /// - Parameter now: The instant to compare each `dueDate` against. Defaults to
    ///   `Date()`; tests pass a fixed date so "past"/"future" is deterministic.
    func refreshOverdueStates(now: Date = Date()) {
        var didChange = false
        for index in promises.indices {
            guard promises[index].state == .planned, promises[index].dueDate < now else { continue }
            guard let next = try? TriageStateMachine.transition(from: .planned, via: .dateNoLongerWorks) else { continue }
            promises[index].state = next
            didChange = true
        }
        if didChange {
            save()
        }
    }

    /// Empties every promise and persists the change — the "delete everything" half
    /// of the Privacy screen's two-step destructive delete
    /// (`01 Product Scope.dc.html` §6, "Download archive and a two-step destructive
    /// delete"). The other half, `SharedDraftStore.clear()`, lives on a separate
    /// store this type has no dependency on — the screen that owns both calls each
    /// one directly rather than this method reaching across stores.
    ///
    /// Same pattern as `add(_:)`/`update(_:)`: mutate the held `promises`, then
    /// persist once.
    func deleteAll() {
        promises = []
        save()
    }

    private func save() {
        guard let data = try? encoder.encode(promises) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from fileURL: URL, decoder: JSONDecoder) -> [Promise] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([Promise].self, from: data)) ?? []
    }
}
