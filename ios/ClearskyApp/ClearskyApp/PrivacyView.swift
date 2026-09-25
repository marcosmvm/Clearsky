import SwiftUI
import ClearskyCore

/// The "Privacy" screen.
///
/// Per `01 Product Scope.dc.html` §6 Screen inventory, "Privacy" — Purpose: "The data
/// promise in full". Key states/actions: "On-device processing, 30-day retention,
/// never sold. Download archive and a two-step destructive delete." §9 "Privacy and
/// data" is where that summary is spelled out in full: "Three commitments carry it,
/// each stated on the Privacy screen and the marketing page in identical words" —
/// this file renders those three commitments verbatim, plus the fourth, strongest one
/// §9 separates out as "the strongest promise, repeated on both surfaces". None of the
/// four are paraphrased here; they are a stated product promise, not marketing copy
/// this screen is free to reword.
///
/// The three commitments (§9, verbatim):
/// - **On your device.** Sorting and drafting run locally wherever the model allows.
/// - **Kept 30 days.** Message text used for sorting is discarded after a month.
/// - **Never sold.** No ad model, no data brokers, no training on user words.
///
/// Plus the strongest promise (§9, verbatim): "Clearsky never sends a message on your
/// behalf."
///
/// ## Download archive
///
/// A real `ShareLink` over `PrivacyArchiveExporter.exportJSON(_:)` — the user's actual
/// `store.promises`, encoded via `Promise`'s existing `Codable` conformance, never a
/// static/fake file. See that type's doc comment for why it is a free function rather
/// than inline in this view's body.
///
/// ## Two-step destructive delete
///
/// `01 Product Scope.dc.html` §7 Flow F ("Leaving"): "You → Privacy → download the
/// archive, then delete everything behind a two-step confirmation". The first tap
/// (`deleteEverythingButton` below) only opens a `.confirmationDialog` — it deletes
/// nothing. The dialog's own destructive-styled confirm button is the second, explicit
/// tap, and only it calls `PrivacyViewModel.confirmDeleteEverything()`, which is the
/// only place in this file that calls `PromiseStore.deleteAll()` and
/// `SharedDraftStore.clear()` — together, so a "leaving" delete wipes both promises
/// and any pending drafts still sitting in the Share Extension's inbox. See
/// `PrivacyViewModel`'s doc comment for why that action lives there, directly
/// testable, rather than inline in a button closure.
struct PrivacyView: View {
    @ObservedObject var store: PromiseStore
    let sharedDraftStore: SharedDraftStore

    @StateObject private var viewModel: PrivacyViewModel

    init(store: PromiseStore, sharedDraftStore: SharedDraftStore) {
        self.store = store
        self.sharedDraftStore = sharedDraftStore
        _viewModel = StateObject(
            wrappedValue: PrivacyViewModel(store: store, sharedDraftStore: sharedDraftStore)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("Privacy")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                Text("The data promise in full.")
                    .font(ClearskyFont.ui(15))
                    .foregroundStyle(ClearskyColor.body)

                commitments

                neverSendsCallout

                downloadArchiveButton

                deleteEverythingSection
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
        .confirmationDialog(
            "Delete everything?",
            isPresented: $viewModel.isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                viewModel.confirmDeleteEverything()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: {
            Text("This permanently deletes every promise and pending draft on this device. This can't be undone.")
        }
    }

    // MARK: - The three commitments (§9, verbatim)

    private var commitments: some View {
        VStack(spacing: ClearskySpacing.xs) {
            ForEach(PrivacyCommitment.allCases, id: \.self) { commitment in
                PrivacyCommitmentRow(commitment: commitment)
            }
        }
    }

    /// The fourth, strongest commitment — §9 names it separately from the other three
    /// ("the strongest promise, repeated on both surfaces") rather than folding it
    /// into the same list, so it renders as its own, more emphasized callout here too.
    private var neverSendsCallout: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xxs) {
            Text("The strongest promise")
                .font(ClearskyFont.ui(11, weight: .semibold))
                .tracking(0.08 * 11)
                .foregroundStyle(ClearskyColor.muted)
            Text("Clearsky never sends a message on your behalf.")
                .font(ClearskyFont.editorial(17))
                .foregroundStyle(ClearskyColor.inkNavy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ClearskySpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .fill(ClearskyColor.inkNavy.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .stroke(ClearskyColor.hairlineStrong, lineWidth: 1)
        )
    }

    // MARK: - Download archive

    /// Real, data-derived export — the same `ShareLink(item:)` pattern
    /// `WeeklyRecapView.shareButton` established for this codebase, sharing a `String`
    /// rather than a file. `viewModel.archiveExportText` is recomputed at share time
    /// off the live `store`, never a stale snapshot.
    private var downloadArchiveButton: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text("YOUR DATA")
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            ShareLink(item: viewModel.archiveExportText) {
                Text("Download archive")
                    .font(ClearskyFont.ui(15, weight: .semibold))
                    .foregroundStyle(ClearskyColor.amberInk)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: ClearskyMetric.minHitTarget)
                    .background(
                        LinearGradient(
                            colors: [ClearskyColor.amberGradientStart, ClearskyColor.amberGradientEnd],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("Every promise you've made, as JSON — \(store.promises.count) right now.")
                .font(ClearskyFont.ui(12))
                .foregroundStyle(ClearskyColor.muted)
        }
    }

    // MARK: - Delete everything (two-step)

    private var deleteEverythingSection: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text("DELETE EVERYTHING")
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            deleteEverythingButton

            if viewModel.didDeleteEverything, let deletedAt = viewModel.deletedAt {
                Text("Deleted \(deletedAt.formatted(date: .abbreviated, time: .shortened)). Promises and pending drafts are gone from this device.")
                    .font(ClearskyFont.ui(12))
                    .foregroundStyle(ClearskyColor.keptGreen)
            } else {
                Text("Removes every promise and pending draft on this device. This can't be undone.")
                    .font(ClearskyFont.ui(12))
                    .foregroundStyle(ClearskyColor.muted)
            }
        }
    }

    /// The first tap only — opens the confirmation dialog above. Never deletes
    /// anything by itself; see `PrivacyViewModel.requestDelete()`.
    private var deleteEverythingButton: some View {
        Button {
            viewModel.requestDelete()
        } label: {
            Text("Delete everything\u{2026}")
                .font(ClearskyFont.ui(15, weight: .semibold))
                .foregroundStyle(ClearskyColor.urgentTerracotta)
                .frame(maxWidth: .infinity)
                .frame(minHeight: ClearskyMetric.minHitTarget)
                .background(
                    RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                        .fill(ClearskyColor.surfacePrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                        .stroke(ClearskyColor.urgentTerracotta.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PrivacyCommitment

/// The three commitments §9 requires stated in identical words on this screen and the
/// marketing site. A closed, `CaseIterable` vocabulary — same reasoning
/// `PromiseNeedsANewPlanExit`/`NotificationCategory` already use elsewhere in this
/// codebase — so nothing here can silently drift into a fourth, invented commitment or
/// reorder the three §9 lists.
enum PrivacyCommitment: CaseIterable {
    case onYourDevice
    case kept30Days
    case neverSold

    /// The bolded label §9 gives each commitment, verbatim.
    var label: String {
        switch self {
        case .onYourDevice: return "On your device."
        case .kept30Days: return "Kept 30 days."
        case .neverSold: return "Never sold."
        }
    }

    /// The sentence that follows the label in §9, verbatim — never paraphrased.
    var detail: String {
        switch self {
        case .onYourDevice: return "Sorting and drafting run locally wherever the model allows."
        case .kept30Days: return "Message text used for sorting is discarded after a month."
        case .neverSold: return "No ad model, no data brokers, no training on user words."
        }
    }
}

private struct PrivacyCommitmentRow: View {
    let commitment: PrivacyCommitment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(commitment.label)
                .font(ClearskyFont.ui(15, weight: .semibold))
                .foregroundStyle(ClearskyColor.inkNavy)
            Text(commitment.detail)
                .font(ClearskyFont.ui(13))
                .foregroundStyle(ClearskyColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ClearskySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
    }
}

// MARK: - PrivacyArchiveExporter

/// The "download archive" JSON, pulled out as a plain, view-independent function —
/// not buried in `PrivacyView`'s body or `PrivacyViewModel` — so a test can prove it
/// encodes the actual promises handed to it, with no view or store involved at all.
/// Same "pull the logic out" reasoning `WeeklyRecap`/`DigestCalculator` already use in
/// this codebase for their own pure computations.
enum PrivacyArchiveExporter {
    /// Encodes `promises` via `Promise`'s existing `Codable` conformance, pretty
    /// printed with sorted keys so the exported text is stable and human-readable,
    /// dates in ISO 8601 (matching `PromiseStore`'s own encoding strategy, so a
    /// re-imported archive round-trips cleanly). Falls back to an empty JSON array
    /// only if encoding itself somehow fails — it never does for `Promise` today —
    /// so callers always get *some* valid JSON rather than an empty string.
    static func exportJSON(_ promises: [Promise]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(promises),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}

// MARK: - PrivacyViewModel

/// Owns the "download archive" export and the two-step "delete everything" action
/// behind `PrivacyView` — pulled out as a plain, directly-testable `ObservableObject`,
/// the same reasoning `NotificationsPermissionView.swift`'s type doc gives for
/// `NotificationsPermissionViewModel`: a test drives `confirmDeleteEverything()`
/// directly against real, disposable `PromiseStore`/`SharedDraftStore` instances, no
/// SwiftUI view-inspection machinery required.
///
/// The two-step delete itself: `requestDelete()` is the first tap — it only flips
/// `isShowingDeleteConfirmation` to show the confirmation dialog, deleting nothing.
/// `confirmDeleteEverything()` is the second, explicit tap inside that dialog — the
/// only method in this type (or anywhere in `PrivacyView`) that calls
/// `store.deleteAll()` and `sharedDraftStore.clear()`. There is no single-tap path to
/// either call.
@MainActor
final class PrivacyViewModel: ObservableObject {
    @Published var isShowingDeleteConfirmation = false
    @Published private(set) var didDeleteEverything = false
    @Published private(set) var deletedAt: Date?

    private let store: PromiseStore
    private let sharedDraftStore: SharedDraftStore

    init(store: PromiseStore, sharedDraftStore: SharedDraftStore) {
        self.store = store
        self.sharedDraftStore = sharedDraftStore
    }

    /// The "download archive" JSON off the live `store` — see
    /// `PrivacyArchiveExporter.exportJSON(_:)`.
    var archiveExportText: String {
        PrivacyArchiveExporter.exportJSON(store.promises)
    }

    /// First tap: opens the confirmation. Deletes nothing.
    func requestDelete() {
        isShowingDeleteConfirmation = true
    }

    /// Dismisses the confirmation without deleting anything — the dialog's own
    /// "Cancel" button.
    func cancelDelete() {
        isShowingDeleteConfirmation = false
    }

    /// Second, explicit tap: the only place `store.deleteAll()` and
    /// `sharedDraftStore.clear()` are ever called, and always together — a "leaving"
    /// delete wipes both promises and any pending drafts still waiting to be triaged.
    ///
    /// - Parameter now: The instant recorded as `deletedAt`. Defaults to `Date()`;
    ///   tests pass a fixed date so the post-delete confirmation text is deterministic.
    func confirmDeleteEverything(now: Date = Date()) {
        store.deleteAll()
        sharedDraftStore.clear()
        didDeleteEverything = true
        deletedAt = now
        isShowingDeleteConfirmation = false
    }
}

// MARK: - Previews

/// Builds a disposable, file-backed `PromiseStore` pre-loaded with `promises` — same
/// isolation pattern `PromisesView.swift`'s `makePreviewStore()` uses, so previews
/// never read or pollute a real device's Documents directory.
@MainActor
private func makePrivacyPreviewStore(promises: [Promise]) -> PromiseStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("privacy-preview-\(UUID().uuidString)")
        .appendingPathExtension("json")
    let store = PromiseStore(fileURL: url)
    for promise in promises {
        store.add(promise)
    }
    return store
}

/// Builds a disposable `UserDefaults` suite-backed `SharedDraftStore` — same isolation
/// pattern `SharedDraftStoreTests` uses, so previews never touch the real App Group.
private func makePrivacyPreviewDraftStore() -> SharedDraftStore {
    let suiteName = "privacy-preview-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return SharedDraftStore(defaults: defaults)
}

private let previewPromises: [Promise] = [
    Promise(
        id: "preview-planned",
        personName: "Maya Chen",
        whatWasPromised: "Send the invoice by Friday",
        dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
        protectedTime: true,
        state: .planned
    ),
    Promise(
        id: "preview-kept",
        personName: "Diego Ruiz",
        whatWasPromised: "Brought the hiking map",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 5),
        protectedTime: false,
        state: .kept
    )
]

#Preview("Privacy") {
    PrivacyView(
        store: makePrivacyPreviewStore(promises: previewPromises),
        sharedDraftStore: makePrivacyPreviewDraftStore()
    )
}

#Preview("Privacy — no promises yet") {
    PrivacyView(
        store: makePrivacyPreviewStore(promises: []),
        sharedDraftStore: makePrivacyPreviewDraftStore()
    )
}
