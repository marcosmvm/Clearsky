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
/// This view only calls `SharedDraftStore`'s existing public methods
/// (`loadAll()`/`remove(id:)`, through the injected `onSaveNewPromise` closure) — its
/// internals are untouched.
struct PendingDraftsView: View {
    let sharedDraftStore: SharedDraftStore
    let onSaveNewPromise: (Promise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [CapturedPromiseDraft] = []
    @State private var draftBeingResolved: CapturedPromiseDraft?
    @State private var isPresentingDraftResolution = false

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: ClearskySpacing.xs) {
                            ForEach(drafts, id: \.id) { draft in
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
            .onAppear { refresh() }
            .sheet(isPresented: $isPresentingDraftResolution) {
                // `CapturedPromiseDraft` is not `Identifiable` (see `ClearskyCore`),
                // so this uses `.sheet(isPresented:)` plus a separately-held
                // `@State` draft rather than `.sheet(item:)`.
                if let draft = draftBeingResolved {
                    NewPromiseView(draft: draft) { promise in
                        onSaveNewPromise(promise)
                        sharedDraftStore.remove(id: draft.id)
                        refresh()
                    }
                }
            }
        }
    }

    private func refresh() {
        drafts = sharedDraftStore.loadAll()
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
    PendingDraftsView(
        sharedDraftStore: SharedDraftStore(defaults: UserDefaults(suiteName: "pending-drafts-preview-empty-\(UUID().uuidString)")!),
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
    return PendingDraftsView(sharedDraftStore: store, onSaveNewPromise: { _ in })
}
