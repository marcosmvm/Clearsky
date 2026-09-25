import SwiftUI
import ClearskyCore

/// The Today screen. Per root README "Screens": Today and Triage "render, per item: a
/// WHY NOW rationale ... an IF YOU DO NOTHING / IF NOT consequence, one recommended
/// action ... and quieter alternatives. Do not reduce either screen to a menu of
/// equal-weight cards."
///
/// ## Demo day vs live
///
/// `01 Product Scope.dc.html` §15 decision 5: the empty state for a user with no
/// inner circle and no connected accounts is "a demo day with sample data, and one
/// tap to connect" — not a hand-off/nag screen. `SampleData.swift` is that demo day's
/// permanent content, not a stand-in to delete. This screen decides which experience
/// to render by asking `ConnectedAccountsState.presentationState`
/// (`ClearskyCore.DataPresentationState`) the same question every other data-driven
/// surface should ask, rather than re-deriving the rule locally: there is no real
/// "connected accounts" toggle built yet, so `hasInnerCircle`/`hasAnyConnectedAccount`
/// are proxied off whether there is any real `Promise` or pending
/// `CapturedPromiseDraft` at all — either one is evidence of a real, in-use account.
///
/// - `.demoDay` renders exactly what this screen always rendered: one full
///   `TriageCardView` for the single most pressing sample item ("Next up"), the rest
///   collapsed into quiet rows ("Later today") — completely unchanged.
/// - `.live` renders the most urgent *real* thing, in priority order: the oldest
///   pending captured draft awaiting confirmation, else the promise soonest due in
///   `.needsANewPlan`, else "All clear" (the screen's existing empty state, reused
///   as-is). This does not reuse `TriageCardView` — a `Promise`/`CapturedPromiseDraft`
///   has no `TriageExplanation` to render one from — but reuses the same design
///   tokens via `RealPrimaryCard` below, so it still matches the app's look.
struct TodayView: View {
    let items: [TriageItem]
    @ObservedObject var promiseStore: PromiseStore
    @ObservedObject var draftsObserver: SharedDraftStoreObserver
    let onSaveNewPromise: (Promise) -> Void
    let onGoToPromises: () -> Void

    @State private var lastActionSummary: String?
    @State private var draftBeingResolved: CapturedPromiseDraft?
    @State private var isPresentingDraftResolution = false

    private var primary: TriageItem? { items.first }
    private var rest: [TriageItem] { items.isEmpty ? [] : Array(items.dropFirst()) }

    /// Read live off `draftsObserver.drafts` rather than calling
    /// `sharedDraftStore.loadAll()` directly — see `SharedDraftStoreObserver`'s doc
    /// comment for why that direct call was the bug: a computed property calling
    /// `loadAll()` has no way to tell SwiftUI when to recompute, so it only looked
    /// fresh when something unrelated forced a re-render. `draftsObserver.drafts` is
    /// `@Published`, so this computed property (and everything under `liveContent`
    /// that reads it) recomputes the instant the underlying store changes.
    private var pendingDrafts: [CapturedPromiseDraft] { draftsObserver.drafts }

    /// See the type-level doc: proxies `ConnectedAccountsState` off whether any real
    /// data exists yet, then reads `.presentationState` off it — same closed decision
    /// §15 decision 5 already defines, not a locally re-derived rule.
    private var presentationState: DataPresentationState {
        let hasRealData = !promiseStore.promises.isEmpty || !pendingDrafts.isEmpty
        let connectedAccountsState = ConnectedAccountsState(
            connectedAccountKinds: [],
            innerCircleCount: hasRealData ? 1 : 0
        )
        return connectedAccountsState.presentationState
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("Today")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                if let summary = lastActionSummary {
                    Text(summary)
                        .font(ClearskyFont.ui(13, weight: .medium))
                        .foregroundStyle(ClearskyColor.keptGreen)
                        .padding(.horizontal, ClearskySpacing.m)
                        .padding(.vertical, ClearskySpacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                                .fill(ClearskyColor.keptGreen.opacity(0.10))
                        )
                }

                switch presentationState {
                case .demoDay:
                    demoDayContent
                case .live:
                    liveContent
                }
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
        .sheet(isPresented: $isPresentingDraftResolution) {
            // `CapturedPromiseDraft` is not `Identifiable` (see `ClearskyCore`), so
            // this uses `.sheet(isPresented:)` plus a separately-held `@State` draft
            // rather than `.sheet(item:)`.
            if let draft = draftBeingResolved {
                NewPromiseView(draft: draft) { promise in
                    onSaveNewPromise(promise)
                    draftsObserver.remove(id: draft.id)
                }
            }
        }
    }

    // MARK: - Demo day (SampleData — unchanged from before this task)

    @ViewBuilder
    private var demoDayContent: some View {
        if let primary {
            VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
                Text("NEXT UP")
                    .font(ClearskyFont.ui(12, weight: .semibold))
                    .tracking(0.08 * 12)
                    .foregroundStyle(ClearskyColor.muted)

                TriageCardView(item: primary) { resolved in
                    lastActionSummary = "\(primary.personName) \u{2192} \(resolved.resultingState.displayName)"
                }
            }
        } else {
            emptyState
        }

        if !rest.isEmpty {
            VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
                Text("LATER TODAY")
                    .font(ClearskyFont.ui(12, weight: .semibold))
                    .tracking(0.08 * 12)
                    .foregroundStyle(ClearskyColor.muted)

                VStack(spacing: ClearskySpacing.xs) {
                    ForEach(rest) { item in
                        LaterTodayRow(item: item)
                    }
                }
            }
        }
    }

    // MARK: - Live (real Promise/CapturedPromiseDraft data)

    @ViewBuilder
    private var liveContent: some View {
        if let draft = pendingDrafts.min(by: { $0.capturedAt < $1.capturedAt }) {
            VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
                Text("NEXT UP")
                    .font(ClearskyFont.ui(12, weight: .semibold))
                    .tracking(0.08 * 12)
                    .foregroundStyle(ClearskyColor.muted)

                RealPrimaryCard(
                    personLabel: "New capture",
                    whatLabel: draft.sharedText,
                    dateLabel: draft.capturedAt.formatted(date: .abbreviated, time: .shortened),
                    whyNow: "Captured \u{B7} not yet a promise",
                    actionLabel: "Turn into a promise"
                ) {
                    draftBeingResolved = draft
                    isPresentingDraftResolution = true
                }
            }
        } else if let needsANewPlan = promiseStore.promises
            .filter({ $0.state == .needsANewPlan })
            .min(by: { $0.dueDate < $1.dueDate }) {
            VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
                Text("NEXT UP")
                    .font(ClearskyFont.ui(12, weight: .semibold))
                    .tracking(0.08 * 12)
                    .foregroundStyle(ClearskyColor.muted)

                RealPrimaryCard(
                    personLabel: needsANewPlan.personName,
                    whatLabel: needsANewPlan.whatWasPromised,
                    dateLabel: needsANewPlan.dueDate.formatted(date: .abbreviated, time: .shortened),
                    whyNow: "\(Outcome.needsANewPlan.displayName) \u{B7} the date stopped working",
                    actionLabel: "Give it a new time"
                ) {
                    onGoToPromises()
                }
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
            Text("All clear")
                .font(ClearskyFont.ui(16, weight: .semibold))
                .foregroundStyle(ClearskyColor.inkNavy)
            Text("Nothing needs you right now.")
                .font(ClearskyFont.ui(14))
                .foregroundStyle(ClearskyColor.muted)
        }
        .padding(ClearskySpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
    }
}

/// A quiet, compact row — deliberately smaller and lower-contrast than the primary
/// `TriageCardView` so "Later today" never competes visually with "Next up". Still
/// shows the item's real recommended action label (from `TriagePresentation`), just
/// without the full WHY NOW / IF NOT body copy or alternative buttons.
private struct LaterTodayRow: View {
    let item: TriageItem

    var body: some View {
        HStack(spacing: ClearskySpacing.m) {
            Circle()
                .fill(ClearskyColor.surfaceSecondary)
                .frame(width: 32, height: 32)
                .overlay(
                    Text(item.initials)
                        .font(ClearskyFont.ui(11, weight: .semibold))
                        .foregroundStyle(ClearskyColor.secondaryInk)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.personName)
                    .font(ClearskyFont.ui(14, weight: .medium))
                    .foregroundStyle(ClearskyColor.body)
                if let recommended = item.presentation.recommended {
                    Text(recommended.source.actionLabel)
                        .font(ClearskyFont.ui(12))
                        .foregroundStyle(ClearskyColor.muted)
                }
            }

            Spacer()

            Text(item.presentation.state.displayName)
                .font(ClearskyFont.ui(11, weight: .medium))
                .foregroundStyle(item.presentation.state.statusColor)
        }
        .padding(.horizontal, ClearskySpacing.m)
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
}

/// The `.live` counterpart to `TriageCardView` for a real `Promise` or
/// `CapturedPromiseDraft` — deliberately simpler, since neither has a
/// `TriageExplanation` to render the full WHY NOW / IF NOT / alternatives layout
/// from. Person/what/date, one WHY NOW-style line, one action button — built from the
/// same `ClearskyColor`/`ClearskyFont`/`ClearskySpacing`/`ClearskyRadius` tokens every
/// other card in the app uses (see `NeedsANewPlanCard` in `PromisesView.swift` for the
/// same pattern), so it matches the app's look without inventing new tokens.
private struct RealPrimaryCard: View {
    let personLabel: String
    let whatLabel: String
    let dateLabel: String
    let whyNow: String
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(personLabel)
                    .font(ClearskyFont.ui(16, weight: .semibold))
                    .foregroundStyle(ClearskyColor.inkNavy)
                Spacer()
                Text(dateLabel)
                    .font(ClearskyFont.ui(12))
                    .foregroundStyle(ClearskyColor.muted)
            }

            Text(whatLabel)
                .font(ClearskyFont.editorial(16))
                .foregroundStyle(ClearskyColor.body)
                .fixedSize(horizontal: false, vertical: true)

            Text(whyNow.uppercased())
                .font(ClearskyFont.ui(11, weight: .semibold))
                .tracking(0.08 * 11)
                .foregroundStyle(ClearskyColor.amberLabelInk)

            Button(action: action) {
                Text(actionLabel)
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
        }
        .padding(ClearskySpacing.l)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Preview

/// Builds a disposable, file-backed `PromiseStore` and a `SharedDraftStoreObserver`
/// over a disposable `UserDefaults` suite — same isolation pattern
/// `PromisesView.swift`'s `makePreviewStore()` uses. Both start empty, so this preview
/// stays on `.demoDay` and keeps rendering `SampleData.triageItems`, exactly as before
/// this task.
@MainActor
private func makeTodayPreviewDependencies() -> (PromiseStore, SharedDraftStoreObserver) {
    let promiseStoreURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("today-view-preview-\(UUID().uuidString)")
        .appendingPathExtension("json")
    let draftsSuiteName = "today-view-preview-\(UUID().uuidString)"
    let draftsDefaults = UserDefaults(suiteName: draftsSuiteName)!
    return (
        PromiseStore(fileURL: promiseStoreURL),
        SharedDraftStoreObserver(store: SharedDraftStore(defaults: draftsDefaults), defaults: draftsDefaults)
    )
}

#Preview {
    let (promiseStore, draftsObserver) = makeTodayPreviewDependencies()
    return TodayView(
        items: SampleData.triageItems,
        promiseStore: promiseStore,
        draftsObserver: draftsObserver,
        onSaveNewPromise: { _ in },
        onGoToPromises: {}
    )
}
