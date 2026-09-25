import SwiftUI
import ClearskyCore

/// "Weekly recap" — the emotional payoff screen. Per `01 Product Scope.dc.html` §6
/// Screen inventory: "A golden-hour sky plate under the light-column pattern, count of
/// times you showed up, named moments, share. Reached from You or the Sunday
/// notification." Flow D (Sunday) continues past this screen into a Digest and "the
/// one thing that slipped" — both are their own screens/tasks, out of scope here; this
/// file only needs the recap itself to exist, compute real numbers off `PromiseStore`,
/// render, and build. Wiring it into real navigation from You/Settings or the Sunday
/// notification is explicitly a later task.
///
/// ## "Count of times you showed up"
///
/// The product's own word for a promise you followed through on is `Outcome.kept`
/// (`DomainDisplay.swift`'s `.displayName` → "Kept", `.statusColor` → `keptGreen`). The
/// count and the "named moments" list below are both driven by `WeeklyRecap`, the
/// testable value type at the bottom of this file — it does the actual filtering so a
/// unit test can prove the "kept in the last 7 days" logic without instantiating this
/// view at all.
///
/// ## "This week" window
///
/// Defined as the 7 days ending `referenceDate` (default `Date()`, overridable — same
/// `now:` pattern `PromiseStore.refreshOverdueStates(now:)` already uses — so this
/// screen is testable/previewable against a fixed instant). `Promise` has no separate
/// "the moment it was actually kept" timestamp — `state` is the only field that
/// changes after creation (see `Promise.swift`) — so `dueDate` is the closest real
/// signal the domain model records today for "when this happened", and is what the
/// window is measured against. See `WeeklyRecap.keptPromises(in:referenceDate:)`'s doc
/// comment for the exact boundary rule.
///
/// ## The golden-hour sky plate
///
/// The design references a painted "golden-hour" splash plate with a light-column
/// pattern laid over it (`CLAUDE_CODE_AUDIT.md` §"Weekly Recap", root `CLAUDE.md`'s
/// plate/pattern map). No bundled gradient or illustration assets exist anywhere in
/// this codebase yet (same stand-in situation the root README already notes for the
/// Anton/Source Serif/Instrument Sans type families) — sourcing or embedding real
/// imagery is explicitly out of scope for this task. `goldenHourPlate` below stands in
/// with the two token gradients closest to a literal golden-hour sky —
/// `ClearskyColor.skyStart`→`.amberGradientEnd` for the sky, thin
/// `.amberGradientStart`-tinted bars over it for the light columns — built entirely
/// from existing `DesignTokens.swift` values, no new hex literals.
struct WeeklyRecapView: View {
    @ObservedObject var store: PromiseStore

    /// The instant "this week" is measured back from. Defaults to `Date()`; tests and
    /// previews pass a fixed date so the 7-day window is deterministic.
    let referenceDate: Date

    init(store: PromiseStore, referenceDate: Date = Date()) {
        self.store = store
        self.referenceDate = referenceDate
    }

    private var recap: WeeklyRecap {
        WeeklyRecap(promises: store.promises, referenceDate: referenceDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("Weekly recap")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                goldenHourPlate

                if recap.keptPromises.isEmpty {
                    emptyState
                } else {
                    tally
                    moments
                    shareButton
                }
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
    }

    // MARK: - Golden-hour sky plate

    private var goldenHourPlate: some View {
        ZStack {
            LinearGradient(
                colors: [ClearskyColor.skyStart, ClearskyColor.amberGradientEnd],
                startPoint: .top,
                endPoint: .bottom
            )

            // Light-column pattern stand-in: evenly spaced vertical bars over the sky
            // gradient, same "62% opacity pattern layer" idea the six splash plates use
            // (root `CLAUDE.md`), built from an existing token rather than a new asset.
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle()
                        .fill(ClearskyColor.amberGradientStart.opacity(0.35))
                        .frame(width: 3)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, ClearskySpacing.xl)
            .padding(.vertical, ClearskySpacing.l)
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.xl, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
    }

    // MARK: - Kept this week

    private var tally: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xxs) {
            Text("\(recap.count)")
                .font(ClearskyFont.display(48))
                .foregroundStyle(ClearskyColor.inkNavy)
                .displayHeadlineStyle()
            Text(recap.count == 1 ? "time you showed up this week" : "times you showed up this week")
                .font(ClearskyFont.ui(14))
                .foregroundStyle(ClearskyColor.muted)
        }
    }

    private var moments: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text("THE MOMENTS")
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            VStack(spacing: ClearskySpacing.xs) {
                ForEach(recap.keptPromises) { promise in
                    MomentRow(promise: promise)
                }
            }
        }
    }

    /// Per the spec's "share" — a real system share sheet over a short text summary of
    /// the recap (`WeeklyRecap.shareText`), not a button that does nothing.
    private var shareButton: some View {
        ShareLink(item: recap.shareText) {
            Text("Share this week")
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

    /// Zero `.kept` promises in the window is an honest, expected outcome for a new or
    /// quiet week — not an error — so this names the situation plainly rather than
    /// rendering a bare "0" with no context, and invents no congratulatory copy the
    /// data doesn't support.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
            Text("Nothing kept yet this week")
                .font(ClearskyFont.ui(16, weight: .semibold))
                .foregroundStyle(ClearskyColor.inkNavy)
            Text("Keep a promise and it will show up here.")
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

/// One named moment: a `.kept` promise's person and what was promised. Deliberately
/// read-only (no tap-to-complete affordance like `PromisesView`'s `PromiseRow`) — a
/// promise reaching this screen is already resolved.
private struct MomentRow: View {
    let promise: Promise

    var body: some View {
        HStack(spacing: ClearskySpacing.m) {
            Circle()
                .fill(ClearskyColor.keptGreen.opacity(0.12))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ClearskyColor.keptGreen)
                )

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

// MARK: - WeeklyRecap

/// The "kept in the last 7 days" computation behind Weekly recap, pulled out as a
/// plain value type — not buried only in `WeeklyRecapView`'s body — so
/// `WeeklyRecap.keptPromises(in:referenceDate:)` can be unit tested directly, with no
/// SwiftUI view rendering involved.
struct WeeklyRecap {
    let referenceDate: Date
    let keptPromises: [Promise]

    var count: Int { keptPromises.count }

    init(promises: [Promise], referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
        self.keptPromises = Self.keptPromises(in: promises, referenceDate: referenceDate)
    }

    /// Every promise in `.kept` whose `dueDate` falls within the 7 days ending
    /// `referenceDate`, inclusive on both ends — i.e. `dueDate` in
    /// `[referenceDate - 7 days, referenceDate]`. A promise in any other `Outcome`
    /// (`.planned`, `.needsANewPlan`, etc.) is excluded regardless of its date. Sorted
    /// most-recent first, since that is the order a recap reads naturally in.
    static func keptPromises(in promises: [Promise], referenceDate: Date = Date()) -> [Promise] {
        let windowStart = Calendar.current.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate
        return promises
            .filter { $0.state == .kept && $0.dueDate >= windowStart && $0.dueDate <= referenceDate }
            .sorted { $0.dueDate > $1.dueDate }
    }

    /// The text summary behind the "share" affordance. Kept short and honest: a
    /// one-line tally plus one line per named moment — never invented copy the data
    /// doesn't support. Callers only present `shareButton` when `keptPromises` is
    /// non-empty, but this still returns an honest string for the empty case so the
    /// type itself never assumes it.
    var shareText: String {
        guard !keptPromises.isEmpty else {
            return "This week on Clearsky: nothing kept yet."
        }
        let header = count == 1
            ? "I showed up once this week on Clearsky:"
            : "I showed up \(count) times this week on Clearsky:"
        let momentLines = keptPromises
            .map { "\u{2022} \($0.personName) \u{2014} \($0.whatWasPromised)" }
            .joined(separator: "\n")
        return "\(header)\n\(momentLines)"
    }
}

// MARK: - Previews

/// Builds a disposable, file-backed `PromiseStore` pre-loaded with `promises` — same
/// isolation pattern `PromisesView.swift`'s `makePreviewStore()` uses, so previews
/// never read or pollute a real device's Documents directory.
@MainActor
private func makeWeeklyRecapPreviewStore(promises: [Promise]) -> PromiseStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("weekly-recap-preview-\(UUID().uuidString)")
        .appendingPathExtension("json")
    let store = PromiseStore(fileURL: url)
    for promise in promises {
        store.add(promise)
    }
    return store
}

private let previewReferenceDate = Date()

/// Several `.kept` promises inside the 7-day window, plus one outside it and one in a
/// different state — exercises the moments list and confirms (visually) that the
/// filter is doing real work, not just rendering everything it's handed.
private let previewKeptThisWeekPromises: [Promise] = [
    Promise(
        id: "preview-kept-1",
        personName: "Maya Chen",
        whatWasPromised: "Sent the invoice",
        dueDate: previewReferenceDate.addingTimeInterval(-60 * 60 * 24 * 1),
        protectedTime: true,
        state: .kept
    ),
    Promise(
        id: "preview-kept-2",
        personName: "Diego Ruiz",
        whatWasPromised: "Brought the hiking map",
        dueDate: previewReferenceDate.addingTimeInterval(-60 * 60 * 24 * 3),
        protectedTime: false,
        state: .kept
    ),
    Promise(
        id: "preview-kept-3",
        personName: "Priya Patel",
        whatWasPromised: "Confirmed the venue",
        dueDate: previewReferenceDate.addingTimeInterval(-60 * 60 * 24 * 6),
        protectedTime: false,
        state: .kept
    ),
    Promise(
        id: "preview-kept-outside-window",
        personName: "Sam Rivera",
        whatWasPromised: "Old coffee catch-up, over a week ago",
        dueDate: previewReferenceDate.addingTimeInterval(-60 * 60 * 24 * 12),
        protectedTime: false,
        state: .kept
    ),
    Promise(
        id: "preview-planned-not-kept",
        personName: "James Okafor",
        whatWasPromised: "Call about the lease renewal",
        dueDate: previewReferenceDate.addingTimeInterval(60 * 60 * 24 * 2),
        protectedTime: false,
        state: .planned
    )
]

#Preview("Weekly recap — several kept") {
    WeeklyRecapView(
        store: makeWeeklyRecapPreviewStore(promises: previewKeptThisWeekPromises),
        referenceDate: previewReferenceDate
    )
}

#Preview("Weekly recap — empty") {
    let promises: [Promise] = [
        Promise(
            id: "preview-empty-planned",
            personName: "James Okafor",
            whatWasPromised: "Call about the lease renewal",
            dueDate: previewReferenceDate.addingTimeInterval(60 * 60 * 24 * 2),
            protectedTime: false,
            state: .planned
        )
    ]
    return WeeklyRecapView(
        store: makeWeeklyRecapPreviewStore(promises: promises),
        referenceDate: previewReferenceDate
    )
}
