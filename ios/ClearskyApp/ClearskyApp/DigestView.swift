import SwiftUI
import ClearskyCore

/// The "Digest" screen: the detail behind the weekly recap.
///
/// Per `01 Product Scope.dc.html` §6 Screen inventory, "Digest" — Purpose: "The detail
/// behind the recap". Key states/actions: "Kept, moved and let-go counts, the moments
/// list, and one thing to watch with a direct route to fix it." Flow D "Sunday": "Recap
/// → digest → the one thing that slipped → straight into that promise's detail to deal
/// with it." This view renders exactly that: three counts, the specific kept/let-go
/// promises behind them ("moments"), and a single most-urgent `.needsANewPlan` promise
/// with a route into `PromiseDetailView`. Weekly Recap is the screen that links out to
/// this one — wiring that link, and wiring this screen into any tab/navigation, is a
/// later task (see the file-level task note); this file only needs to compile, render
/// real numbers off `PromiseStore`, and be previewable/testable standalone. It adds no
/// call site into `RootView.swift`, `TodayView.swift`, `PromisesView.swift`,
/// `PromiseStore.swift` or `WeeklyRecapView.swift`.
///
/// **Kept** / **Let go**: `Outcome.kept` / `Outcome.released` — a straight count (and
/// the underlying promise list, for the moments section) of whatever is currently in
/// each state. Not scoped to "this week": `Promise` carries no completed/released
/// timestamp (only `dueDate`, which is fixed at creation and never updated once a
/// promise is `.kept`/`.released`), so there is no honest way to tell a promise kept
/// yesterday from one kept a month ago. Totals-to-date, not a rolling week, is the
/// accurate thing to show given the data that actually exists.
///
/// **Moved**: deliberately has no count anywhere in this file. The only path a promise
/// takes out of "moved" territory is `TriageStateMachine.table`'s
/// `(from: .needsANewPlan, action: .reschedulePlan, to: .planned)` row
/// (`PromisesView.reschedule`/`PromiseDetailView.giveItANewTime`) — and that transition
/// rebuilds the promise back into the exact same `.planned` state a promise that was
/// *never* rescheduled sits in, with no flag, counter or timestamp recording that it
/// happened (`Promise`'s fields: `id`, `personName`, `whatWasPromised`, `dueDate`,
/// `sourceText`, `protectedTime`, `state`, `calendarEventIdentifier` — nothing else).
/// So "how many were moved" cannot be answered from data this codebase actually
/// persists today; `DigestCountsRow` renders "—" with a caption saying so, rather than
/// inventing a number. Fixing this for real needs a schema change to `Promise` (e.g. a
/// `rescheduleCount`/`history` field) — explicitly out of scope: this task adds new
/// `ClearskyApp` files only, no `ClearskyCore` changes.
///
/// **One thing to watch**: the single most urgent `.needsANewPlan` promise, selected by
/// `DigestCalculator.oneThingToWatch(in:referenceDate:)` — see that function's doc
/// comment for the selection rule and why "oldest-unresolved" was chosen over
/// "soonest-due". Rendered via `DigestOneThingToWatchCard` inside a `NavigationLink` to
/// `PromiseDetailView(promise:store:)` (that init fits directly — no fallback summary
/// needed), matching flow D's "straight into that promise's detail to deal with it."
/// Assumes this view already lives inside a `NavigationStack` supplied by its eventual
/// container (the same pattern `RootView` uses per tab) — it does not open its own.
///
/// All the counting/selection logic lives in `DigestCalculator` below, not in this
/// view's body, so it is directly unit-testable — same split
/// `PromisesView.reschedule(_:newDueDate:calendarService:)` uses to keep its core logic
/// testable without a view.
struct DigestView: View {
    @ObservedObject var store: PromiseStore

    /// The instant "today" is, for computing how long the "one thing to watch" promise
    /// has been sitting unresolved. Defaults to `Date()`; a test or preview passes a
    /// fixed date so that computation is deterministic — same pattern
    /// `PromiseStore.refreshOverdueStates(now:)` already uses.
    let referenceDate: Date

    init(store: PromiseStore, referenceDate: Date = Date()) {
        self.store = store
        self.referenceDate = referenceDate
    }

    var body: some View {
        let summary = DigestCalculator.summary(for: store.promises, referenceDate: referenceDate)

        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("Digest")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                if summary.isEmpty {
                    emptyState
                } else {
                    DigestCountsRow(summary: summary)

                    if !summary.keptPromises.isEmpty {
                        momentsSection(
                            title: "Kept",
                            promises: summary.keptPromises,
                            tint: ClearskyColor.keptGreen
                        )
                    }

                    if !summary.releasedPromises.isEmpty {
                        momentsSection(
                            title: "Let go",
                            promises: summary.releasedPromises,
                            tint: ClearskyColor.muted
                        )
                    }

                    oneThingToWatchSection(summary: summary)
                }
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
    }

    // MARK: - Moments list

    /// The specific promises behind a Kept/Let-go count — "the moments list" per the
    /// spec, not just a total. Sorted most-recent-`dueDate`-first, the only date this
    /// screen has to sort by (see the file doc comment on why there is no completion
    /// timestamp to sort by instead).
    @ViewBuilder
    private func momentsSection(title: String, promises: [Promise], tint: Color) -> some View {
        let sorted = promises.sorted { $0.dueDate > $1.dueDate }

        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text(title.uppercased())
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            VStack(spacing: ClearskySpacing.xs) {
                ForEach(sorted) { promise in
                    DigestMomentRow(promise: promise, tint: tint)
                }
            }
        }
    }

    // MARK: - One thing to watch

    @ViewBuilder
    private func oneThingToWatchSection(summary: DigestCalculator.Summary) -> some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text("ONE THING TO WATCH")
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            if let watch = summary.oneThingToWatch {
                NavigationLink {
                    PromiseDetailView(promise: watch.promise, store: store)
                } label: {
                    DigestOneThingToWatchCard(watch: watch)
                }
                .buttonStyle(.plain)
            } else {
                Text("Nothing needs a new plan right now.")
                    .font(ClearskyFont.ui(13))
                    .foregroundStyle(ClearskyColor.muted)
            }
        }
    }

    // MARK: - Empty state

    /// Honest empty state: no kept, no let-go, and no `.needsANewPlan` promise to
    /// watch — there is nothing at all to report yet.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
            Text("Nothing to report yet")
                .font(ClearskyFont.ui(16, weight: .semibold))
                .foregroundStyle(ClearskyColor.inkNavy)
            Text("Once you keep, let go, or need a new plan on a promise, it shows up here.")
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

// MARK: - DigestCalculator

/// Pure, view-independent counting/selection logic for the Digest screen. No SwiftUI
/// dependency — every function here takes a `[Promise]` and returns plain data, so it
/// is directly testable (`DigestCalculatorTests.swift`) without instantiating a view.
enum DigestCalculator {
    /// The single most urgent `.needsANewPlan` promise, plus how long it has been
    /// sitting unresolved as of `referenceDate`.
    struct OneThingToWatch: Equatable {
        let promise: Promise
        /// Whole days between the promise's `dueDate` and `referenceDate`, floored at
        /// 0. Computed with `Calendar.current`, the same calendar every other date
        /// display in this app layer implicitly uses via `Date.formatted(...)`.
        let daysSinceDue: Int
    }

    /// Everything `DigestView` renders, computed once per body evaluation.
    struct Summary: Equatable {
        let keptPromises: [Promise]
        let releasedPromises: [Promise]
        let oneThingToWatch: OneThingToWatch?

        var keptCount: Int { keptPromises.count }
        var releasedCount: Int { releasedPromises.count }

        /// Nothing at all to report: no kept, no let-go, no `.needsANewPlan` promise.
        var isEmpty: Bool {
            keptPromises.isEmpty && releasedPromises.isEmpty && oneThingToWatch == nil
        }
    }

    static func summary(for promises: [Promise], referenceDate: Date = Date()) -> Summary {
        Summary(
            keptPromises: promises.filter { $0.state == .kept },
            releasedPromises: promises.filter { $0.state == .released },
            oneThingToWatch: oneThingToWatch(in: promises, referenceDate: referenceDate)
        )
    }

    /// Selection rule — **oldest-unresolved**, not soonest-due.
    ///
    /// Every `.needsANewPlan` promise reaches that state through
    /// `PromiseStore.refreshOverdueStates(now:)`, the only normal path into it, which
    /// only ever moves a promise there once its `dueDate` has *already* passed. So
    /// "soonest due" among `.needsANewPlan` promises would just pick whichever one
    /// slipped most recently — the one closest to having still been on track, which is
    /// the least urgent of the group, not the most. Picking the promise with the
    /// *earliest* `dueDate` instead surfaces the one that has gone the longest without
    /// a decision — genuinely the one thing most overdue for either a new time or being
    /// let go. Ties (identical `dueDate`) break on `id` so the pick is deterministic.
    ///
    /// Returns `nil` when there is no `.needsANewPlan` promise at all.
    static func oneThingToWatch(in promises: [Promise], referenceDate: Date = Date()) -> OneThingToWatch? {
        let candidates = promises.filter { $0.state == .needsANewPlan }
        guard let earliest = candidates.min(by: { lhs, rhs in
            lhs.dueDate != rhs.dueDate ? lhs.dueDate < rhs.dueDate : lhs.id < rhs.id
        }) else {
            return nil
        }
        return OneThingToWatch(
            promise: earliest,
            daysSinceDue: daysSinceDue(dueDate: earliest.dueDate, referenceDate: referenceDate)
        )
    }

    private static func daysSinceDue(dueDate: Date, referenceDate: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: dueDate, to: referenceDate).day ?? 0
        return max(days, 0)
    }
}

// MARK: - Subviews

/// The three counts: Kept, Let go, Moved. Moved always renders "—" — see the file doc
/// comment on `DigestView` for why that count has no legitimate data source today.
private struct DigestCountsRow: View {
    let summary: DigestCalculator.Summary

    var body: some View {
        HStack(spacing: ClearskySpacing.sm) {
            DigestCountCard(label: "Kept", value: "\(summary.keptCount)", valueColor: ClearskyColor.keptGreen)
            DigestCountCard(label: "Let go", value: "\(summary.releasedCount)", valueColor: ClearskyColor.muted)
            DigestCountCard(
                label: "Moved",
                value: "\u{2014}",
                valueColor: ClearskyColor.muted,
                caption: "Not tracked yet"
            )
        }
    }
}

private struct DigestCountCard: View {
    let label: String
    let value: String
    let valueColor: Color
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xxs) {
            Text(value)
                .font(ClearskyFont.display(24))
                .foregroundStyle(valueColor)
            Text(label.uppercased())
                .font(ClearskyFont.ui(11, weight: .semibold))
                .tracking(0.08 * 11)
                .foregroundStyle(ClearskyColor.muted)
            if let caption {
                Text(caption)
                    .font(ClearskyFont.ui(10))
                    .foregroundStyle(ClearskyColor.muted)
            }
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
        .accessibilityElement(children: .combine)
    }
}

/// One row in "the moments list" — a specific kept or let-go promise, not just a
/// number. Read-only: unlike `PromisesView.PromiseRow`, nothing here is tappable to
/// change state (Kept/Released are already resolved).
private struct DigestMomentRow: View {
    let promise: Promise
    let tint: Color

    var body: some View {
        HStack(spacing: ClearskySpacing.m) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(promise.personName)
                    .font(ClearskyFont.ui(14, weight: .medium))
                    .foregroundStyle(ClearskyColor.body)
                Text(promise.whatWasPromised)
                    .font(ClearskyFont.ui(12))
                    .foregroundStyle(ClearskyColor.muted)
                    .lineLimit(2)
            }

            Spacer()

            Text(promise.dueDate.formatted(date: .abbreviated, time: .omitted))
                .font(ClearskyFont.ui(11))
                .foregroundStyle(ClearskyColor.muted)
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

/// The "one thing to watch" card — tappable (via the `NavigationLink` that wraps it in
/// `DigestView`) straight into that promise's `PromiseDetailView`, per flow D.
private struct DigestOneThingToWatchCard: View {
    let watch: DigestCalculator.OneThingToWatch

    private var promise: Promise { watch.promise }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ClearskySpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(promise.personName)
                    .font(ClearskyFont.ui(16, weight: .semibold))
                    .foregroundStyle(ClearskyColor.inkNavy)
                Text(promise.whatWasPromised)
                    .font(ClearskyFont.editorial(14))
                    .foregroundStyle(ClearskyColor.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(daysLabel)
                    .font(ClearskyFont.ui(12, weight: .semibold))
                    .foregroundStyle(Outcome.needsANewPlan.statusColor)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(ClearskyColor.muted)
        }
        .padding(ClearskySpacing.l)
        // "44px minimum hit target, everywhere, no exceptions" (root README, Hard
        // rules) — explicit here since this whole card is the `NavigationLink`'s tap
        // target, same as `NeedsANewPlanCard`'s exit buttons enforce it explicitly
        // rather than relying on the padded content happening to be tall enough.
        .frame(minHeight: ClearskyMetric.minHitTarget)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
    }

    private var daysLabel: String {
        switch watch.daysSinceDue {
        case 0: return "Due today"
        case 1: return "1 day overdue"
        default: return "\(watch.daysSinceDue) days overdue"
        }
    }
}

// MARK: - Previews

/// Sample promises covering Kept, Released and two `.needsANewPlan` candidates (so the
/// preview exercises the selection rule, not just the presence of one candidate).
private let previewPromises: [Promise] = [
    Promise(
        id: "preview-kept-1",
        personName: "Diego Ruiz",
        whatWasPromised: "Brought the hiking map",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 5),
        protectedTime: false,
        state: .kept
    ),
    Promise(
        id: "preview-kept-2",
        personName: "Maya Chen",
        whatWasPromised: "Sent the invoice on time",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 2),
        protectedTime: false,
        state: .kept
    ),
    Promise(
        id: "preview-released-1",
        personName: "Sam Rivera",
        whatWasPromised: "Old coffee catch-up, no longer happening",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 10),
        protectedTime: false,
        state: .released
    ),
    Promise(
        id: "preview-needs-a-new-plan-1",
        personName: "James Okafor",
        whatWasPromised: "Call about the lease renewal",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 6),
        protectedTime: false,
        state: .needsANewPlan
    ),
    Promise(
        id: "preview-needs-a-new-plan-2",
        personName: "Priya Patel",
        whatWasPromised: "Confirm the venue for Saturday",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 1),
        protectedTime: false,
        state: .needsANewPlan
    )
]

/// Builds a disposable, file-backed store pre-loaded with `promises` — same isolation
/// pattern `PromisesView.swift`'s `makePreviewStore()` uses, so previews never read or
/// pollute a real device's Documents directory.
@MainActor
private func makePreviewStore(with promises: [Promise]) -> PromiseStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("digest-view-preview-\(UUID().uuidString)")
        .appendingPathExtension("json")
    let store = PromiseStore(fileURL: url)
    for promise in promises {
        store.add(promise)
    }
    return store
}

#Preview("Digest — mix") {
    NavigationStack {
        DigestView(store: makePreviewStore(with: previewPromises))
    }
}

#Preview("Digest — empty") {
    NavigationStack {
        DigestView(store: makePreviewStore(with: []))
    }
}
