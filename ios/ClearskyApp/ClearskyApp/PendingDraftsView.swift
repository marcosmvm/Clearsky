import SwiftUI
import ClearskyCore

/// The Share Extension's inbox, made reachable.
///
/// `ClearskyShareExtension` (PR #16) appends a `CapturedPromiseDraft` to
/// `SharedDraftStore` the instant a person shares text into Clearsky, but until this
/// view existed nothing in the app ever called `SharedDraftStore.loadAll()` — a
/// capture had no way to reach a person again. This screen lists every pending draft,
/// oldest first, and lets a person turn one into a real `Promise` via
/// `NewPromiseView(draft:onSave:)`, or dismiss without acting (the draft stays in the
/// inbox either way — only resolving it through `NewPromiseView`'s save removes it,
/// via `onSaveNewPromise` calling `SharedDraftStore.remove(id:)`).
///
/// Reads through `SharedDraftStoreObserver` (`draftsObserver.drafts`) rather than
/// holding a raw `SharedDraftStore` and its own `@State` copy.
///
/// This view previously kept `@State private var drafts` populated with an explicit
/// `refresh()` called from `.onAppear` and again after every resolved draft — a
/// reasonable pattern (it covers "the sheet just opened" and "a draft was just
/// resolved"), but it still missed the same gap `RootView`'s badge and `TodayView`'s
/// primary card had: if this sheet was already open when the person backgrounded the
/// app to share into the Share Extension and then returned, nothing here would have
/// re-triggered `.onAppear`, so the new draft would not have shown up until the sheet
/// was closed and reopened. Routing through `draftsObserver` closes that gap the same
/// way it closes it everywhere else, and removes the need for the manual `refresh()`
/// calls entirely — see `SharedDraftStoreObserver`'s doc comment.
struct PendingDraftsView: View {
    @ObservedObject var draftsObserver: SharedDraftStoreObserver
    let onSaveNewPromise: (Promise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftBeingResolved: CapturedPromiseDraft?
    @State private var isPresentingDraftResolution = false

    var body: some View {
        NavigationStack {
            Group {
                if draftsObserver.drafts.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: ClearskySpacing.xs) {
                            ForEach(draftsObserver.drafts, id: \.id) { draft in
                                Button {
                                    draftBeingResolved = draft
                                    isPresentingDraftResolution = true
                                } label: {
                                    row(for: draft)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(ClearskySpacing.l)
                    }
                }
            }
            .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
            .navigationTitle("Captured")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ClearskyColor.secondaryInk)
                }
            }
            .sheet(isPresented: $isPresentingDraftResolution) {
                // `CapturedPromiseDraft` is not `Identifiable` (see `ClearskyCore`),
                // so this uses `.sheet(isPresented:)` plus a separately-held
                // `@State` draft rather than `.sheet(item:)`.
                if let draft = draftBeingResolved {
                    NewPromiseView(draft: draft) { promise in
                        onSaveNewPromise(promise)
                        draftsObserver.remove(id: draft.id)
                    }
                }
            }
        }
    }

    private func row(for draft: CapturedPromiseDraft) -> some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xxs) {
            Text(draft.sharedText)
                .font(ClearskyFont.editorial(15))
                .foregroundStyle(ClearskyColor.body)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(draft.capturedAt.formatted(date: .abbreviated, time: .shortened))
                .font(ClearskyFont.ui(12))
                .foregroundStyle(ClearskyColor.muted)
        }
        .padding(ClearskySpacing.m)
        .frame(minHeight: ClearskyMetric.minHitTarget)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
            Text("Nothing captured")
                .font(ClearskyFont.ui(16, weight: .semibold))
                .foregroundStyle(ClearskyColor.inkNavy)
            Text("Anything you share into Clearsky shows up here.")
                .font(ClearskyFont.ui(14))
                .foregroundStyle(ClearskyColor.muted)
        }
        .padding(ClearskySpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

#Preview("Empty") {
    let defaults = UserDefaults(suiteName: "pending-drafts-preview-empty-\(UUID().uuidString)")!
    return PendingDraftsView(
        draftsObserver: SharedDraftStoreObserver(store: SharedDraftStore(defaults: defaults), defaults: defaults),
        onSaveNewPromise: { _ in }
    )
}

#Preview("With drafts") {
    let defaults = UserDefaults(suiteName: "pending-drafts-preview-\(UUID().uuidString)")!
    let store = SharedDraftStore(defaults: defaults)
    store.append(
        CapturedPromiseDraft(
            id: "preview-draft-1",
            sharedText: "Can you send the invoice by Friday?",
            capturedAt: Date().addingTimeInterval(-3600),
            source: .text
        )
    )
    store.append(
        CapturedPromiseDraft(
            id: "preview-draft-2",
            sharedText: "Following up — any update on the lease renewal?",
            capturedAt: Date(),
            source: .email
        )
    )
    let draftsObserver = SharedDraftStoreObserver(store: store, defaults: defaults)
    return PendingDraftsView(draftsObserver: draftsObserver, onSaveNewPromise: { _ in })
}
