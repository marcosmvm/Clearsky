import Foundation
import ClearskyCore

/// Read/write access to the App Group inbox of captured Share Sheet drafts.
///
/// This file lives in `Shared/` and is listed in both `ClearskyApp` and
/// `ClearskyShareExtension`'s `sources:` in `project.yml` (see the comment there) so
/// one compiled copy of the logic serves both targets — the extension appends a draft
/// the instant a person shares into it, the app reads the inbox later to build the
/// confirm/edit screen (a separate task). The `UserDefaults` instance is injected
/// rather than constructed here: production call sites pass
/// `UserDefaults(suiteName: SharedDraftStore.appGroupIdentifier)`, tests pass a
/// disposable suite and remove it in `tearDown` so runs never see stale drafts.
struct SharedDraftStore {
    /// The App Group both targets declare in their entitlements
    /// (`ClearskyApp.entitlements` and `ClearskyShareExtension.entitlements`).
    static let appGroupIdentifier = "group.com.marcosmvm.clearsky"

    private static let draftsKey = "com.marcosmvm.clearsky.capturedPromiseDrafts"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Appends one draft to the end of the inbox, oldest first. If the existing
    /// contents fail to decode (a future schema change, a corrupt write) this starts
    /// a fresh inbox with just the new draft rather than throwing — capture must
    /// never crash the host app or the extension.
    func append(_ draft: CapturedPromiseDraft) {
        var drafts = loadAll()
        drafts.append(draft)
        save(drafts)
    }

    /// Every drafted capture still waiting to be triaged, oldest first.
    func loadAll() -> [CapturedPromiseDraft] {
        guard let data = defaults.data(forKey: Self.draftsKey) else { return [] }
        return (try? decoder.decode([CapturedPromiseDraft].self, from: data)) ?? []
    }

    /// Removes one draft by id, e.g. once the confirm/edit screen has resolved it.
    func remove(id: String) {
        save(loadAll().filter { $0.id != id })
    }

    /// Empties the inbox entirely.
    func clear() {
        defaults.removeObject(forKey: Self.draftsKey)
    }

    private func save(_ drafts: [CapturedPromiseDraft]) {
        guard let data = try? encoder.encode(drafts) else { return }
        defaults.set(data, forKey: Self.draftsKey)
    }
}
