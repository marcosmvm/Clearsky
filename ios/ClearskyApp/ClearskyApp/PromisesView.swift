import SwiftUI
import ClearskyCore

/// The Promises list: every commitment the user has captured or been captured for,
/// grouped by who owns the next move — not by raw status.
///
/// Mirrors `PromiseOwnership.swift` and `CLAUDE_CODE_AUDIT.md` §"Promise ownership"
/// exactly: four sections, in this order — Yours to keep, Not your move, Kept,
/// Released — each titled with `PromiseOwnershipGroup.displayTitle` verbatim
/// (`PromiseOwnershipGroup.allCases` is already declared in that order, so this view
/// never hand-rolls a second ordering to drift out of sync with it). A promise is
/// placed by `PromiseOwnership.group(for:)` alone; a promise whose group resolves to
/// `nil` (the three triage-only `Outcome` cases) is filtered out and never rendered.
///
/// Within "Yours to keep", a promise in `.needsANewPlan` renders as
/// `NeedsANewPlanCard` with the three named exits (`PromiseNeedsANewPlanExit`,
/// verbatim labels) instead of the plain `PromiseRow` every other promise gets.
///
/// This view never talks to `PromiseStore` except through the injected instance —
/// same "no hidden state" pattern as `NewPromiseView`. A later integration task wires
/// this into `RootView`'s tab bar (see the task note on `NewPromiseView`); this file
/// only needs to compile and be testable/previewable standalone.
struct PromisesView: View {
    @ObservedObject var store: PromiseStore

    /// Creates and removes the real calendar holds a protected-time reschedule needs
    /// — see `reschedule(_:newDueDate:calendarService:)` below. Same injected-not-
    /// singleton pattern `RootView` already uses for its own `calendarService`.
    let calendarService: CalendarHolding

    /// The promise mid-reschedule, if any — drives the "Give it a new time" sheet.
    /// `Promise` is `Identifiable`, so `.sheet(item:)` can key directly off it.
    @State private var reschedulingPromise: Promise?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                Text("Promises")
                    .font(ClearskyFont.display(28))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()
                    .padding(.top, ClearskySpacing.m)

                if store.promises.isEmpty {
                    emptyState
                } else {
                    ForEach(PromiseOwnershipGroup.allCases, id: \.self) { group in
                        let promisesInGroup = promises(in: group)
                        if !promisesInGroup.isEmpty {
                            section(group: group, promises: promisesInGroup)
                        }
                    }
                }
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
        .sheet(item: $reschedulingPromise) { promise in
            GiveItANewTimeSheet(promise: promise) { newDueDate in
                giveItANewTime(promise, newDueDate: newDueDate)
            }
        }
    }

    /// Every promise whose `Outcome` maps to `group` via `PromiseOwnership.group(for:)`.
    private func promises(in group: PromiseOwnershipGroup) -> [Promise] {
        store.promises.filter { PromiseOwnership.group(for: $0.state) == group }
    }

    @ViewBuilder
    private func section(group: PromiseOwnershipGroup, promises: [Promise]) -> some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            Text(group.displayTitle.uppercased())
                .font(ClearskyFont.ui(12, weight: .semibold))
                .tracking(0.08 * 12)
                .foregroundStyle(ClearskyColor.muted)

            VStack(spacing: ClearskySpacing.xs) {
                ForEach(promises) { promise in
                    row(for: promise)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for promise: Promise) -> some View {
        if promise.state == .needsANewPlan {
            NeedsANewPlanCard(
                promise: promise,
                onKeepIt: {
                    // "Keep it": no state change. The plan still stands as-is — this
                    // just dismisses the exit affordance, per
                    // `PromiseNeedsANewPlanExit.keepIt`'s doc comment.
                },
                onGiveItANewTime: { reschedulingPromise = promise },
                onLetItGo: { letItGo(promise) }
            )
        } else {
            PromiseRow(
                promise: promise,
                // Per `PromiseOwnership.isDirectlyCompletable(_:)`: only `.planned`
                // ever renders a tap-to-complete affordance. `.waitingOnThem` (“Not
                // your move”) is checked explicitly here — never assumed from which
                // section this row happens to render in — and always renders the
                // read-only dashed circle instead.
                isDirectlyCompletable: PromiseOwnership.isDirectlyCompletable(promise.state),
                isWaitingOnThem: PromiseOwnership.group(for: promise.state) == .notYourMove,
                onComplete: { markKept(promise) }
            )
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
            Text("No promises yet")
                .font(ClearskyFont.ui(16, weight: .semibold))
                .foregroundStyle(ClearskyColor.inkNavy)
            Text("Promises you capture or make show up here.")
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

    // MARK: - Actions

    /// "Give it a new time": resolves the rescheduled `Promise` (and its calendar
    /// side effects, for a protected promise) via `reschedule(_:newDueDate:
    /// calendarService:)` below, then saves through the store. Wrapped in a `Task`
    /// because that resolution is `async` — creating/removing a calendar hold is a
    /// real `EKEventStore` round trip — same "fire a `Task`, save when it resolves"
    /// shape `RootView.handleSavedPromise`/`createCalendarHold` already use for the
    /// same reason.
    private func giveItANewTime(_ promise: Promise, newDueDate: Date) {
        Task {
            guard let updated = await Self.reschedule(
                promise,
                newDueDate: newDueDate,
                calendarService: calendarService
            ) else { return }
            store.update(updated)
        }
    }

    /// The actual reschedule logic, pulled out of `giveItANewTime` as a static
    /// function (rather than a private instance method) so a test can call it
    /// directly with `MockCalendarService` — no view, no real `EKEventStore`, no
    /// `PromiseStore` — and assert on the `Promise` it returns.
    ///
    /// Resolves the new state via `TriageStateMachine.transition(from:
    /// .needsANewPlan, via: .reschedulePlan)`, replaces `dueDate` with the picked
    /// value, then handles the calendar hold this promise may be carrying:
    ///
    /// - `protectedTime == false`: a promise like this never has a hold in the first
    ///   place (see `Promise.calendarEventIdentifier`'s doc comment) — no calendar
    ///   calls are made, and the result's identifier is `nil`, preserving that
    ///   invariant rather than assuming it.
    /// - `protectedTime == true`: this is the fix for the real bug this function
    ///   exists to close — rescheduling used to build the new `Promise` through the
    ///   initializer without forwarding `calendarEventIdentifier` at all, so it
    ///   silently defaulted to `nil`: the *old* hold was never removed (it sat
    ///   orphaned on the calendar at the stale time, forever) and the rescheduled
    ///   promise got no new hold. Here, if an old identifier exists it is removed via
    ///   `calendarService.removeHold(eventIdentifier:)` before a new hold is created
    ///   for `newDueDate` via `calendarService.createHold(for:)` — same 30-minute
    ///   duration convention `RootView.createCalendarHold(for:)` uses — and the
    ///   returned identifier becomes the updated promise's `calendarEventIdentifier`.
    ///
    /// Every calendar call is wrapped so a failure never blocks the reschedule
    /// itself — same "the promise is already saved either way" pattern
    /// `RootView.createCalendarHold(for:)` uses:
    /// - Access denied/failed: the *old* identifier is left attached rather than
    ///   dropped, since nothing was actually removed — the hold likely still sits on
    ///   the calendar at the old time, and keeping the identifier means a later
    ///   reschedule attempt can still find and remove it.
    /// - Access granted but the old hold's removal or the new hold's creation fails:
    ///   the identifier is cleared to `nil` once removal has actually been
    ///   attempted, rather than kept pointing at an identifier that may no longer
    ///   resolve to anything.
    ///
    /// Returns `nil` (matching the original guard-and-return-early behavior) only if
    /// the state transition itself is rejected — which the fixed `.needsANewPlan` →
    /// `.reschedulePlan` table entry never actually does today.
    static func reschedule(
        _ promise: Promise,
        newDueDate: Date,
        calendarService: CalendarHolding
    ) async -> Promise? {
        guard let next = try? TriageStateMachine.transition(from: .needsANewPlan, via: .reschedulePlan) else {
            return nil
        }

        var updated = Promise(
            id: promise.id,
            personName: promise.personName,
            whatWasPromised: promise.whatWasPromised,
            dueDate: newDueDate,
            sourceText: promise.sourceText,
            protectedTime: promise.protectedTime,
            state: next,
            calendarEventIdentifier: promise.protectedTime ? promise.calendarEventIdentifier : nil
        )

        guard promise.protectedTime else { return updated }

        let accessGranted = (try? await calendarService.requestAccess()) ?? false
        guard accessGranted else { return updated }

        if let oldIdentifier = promise.calendarEventIdentifier {
            try? await calendarService.removeHold(eventIdentifier: oldIdentifier)
            updated.calendarEventIdentifier = nil
        }

        do {
            let block = ProtectedTimeBlock(
                id: promise.id,
                start: newDueDate,
                end: newDueDate.addingTimeInterval(30 * 60),
                ownerTitle: promise.whatWasPromised,
                ownerDetail: "With \(promise.personName)"
            )
            updated.calendarEventIdentifier = try await calendarService.createHold(for: block)
        } catch {
            // No writable calendar, or the write itself failed. The old hold (if
            // any) is already removed above either way — the reschedule of the
            // promise's date must still succeed and save even though this promise
            // ends up with no calendar hold attached.
        }

        return updated
    }

    /// "Let it go": resolves via `TriageStateMachine.transition(from: .needsANewPlan,
    /// via: .letGo)`.
    private func letItGo(_ promise: Promise) {
        guard let next = try? TriageStateMachine.transition(from: .needsANewPlan, via: .letGo) else { return }
        var updated = promise
        updated.state = next
        store.update(updated)
    }

    /// The direct tap-to-complete affordance `PromiseOwnership.isDirectlyCompletable`
    /// governs — only ever wired to a control where that returns `true` (today, only
    /// `.planned`, via `TriageStateMachine.table`'s one `.completeCommitment` row).
    private func markKept(_ promise: Promise) {
        guard let next = try? TriageStateMachine.transition(from: promise.state, via: .completeCommitment) else { return }
        var updated = promise
        updated.state = next
        store.update(updated)
    }
}

/// A promise in `.needsANewPlan`: the plan still stands, but the date stopped
/// working. Renders the three honest, non-shaming exits `CLAUDE_CODE_AUDIT.md` and
/// the root `README.md` both require verbatim — "keep it, give it a new time, let it
/// go" — via `PromiseNeedsANewPlanExit.allCases`/`.displayLabel`, never hand-typed
/// copy. The status pill reads `Outcome.needsANewPlan.displayName` ("Needs a new
/// plan") for the same reason: the one canonical word for this state, sourced from
/// `DomainDisplay.swift`, never a literal string that could drift from it.
private struct NeedsANewPlanCard: View {
    let promise: Promise
    let onKeepIt: () -> Void
    let onGiveItANewTime: () -> Void
    let onLetItGo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            header

            Text(promise.whatWasPromised)
                .font(ClearskyFont.editorial(15))
                .foregroundStyle(ClearskyColor.body)
                .fixedSize(horizontal: false, vertical: true)

            exits
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(promise.personName)
                    .font(ClearskyFont.ui(16, weight: .semibold))
                    .foregroundStyle(ClearskyColor.inkNavy)
                Text(promise.dueDate.formatted(date: .abbreviated, time: .shortened))
                    .font(ClearskyFont.ui(12))
                    .foregroundStyle(ClearskyColor.muted)
            }

            Spacer()

            Text(Outcome.needsANewPlan.displayName)
                .font(ClearskyFont.ui(12, weight: .semibold))
                .foregroundStyle(Outcome.needsANewPlan.statusColor)
                .padding(.horizontal, ClearskySpacing.s)
                .padding(.vertical, ClearskySpacing.xxs)
                .background(
                    Capsule().fill(Outcome.needsANewPlan.statusColor.opacity(0.12))
                )
        }
    }

    private var exits: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
            ForEach(PromiseNeedsANewPlanExit.allCases, id: \.self) { exit in
                Button {
                    switch exit {
                    case .keepIt: onKeepIt()
                    case .giveItANewTime: onGiveItANewTime()
                    case .letItGo: onLetItGo()
                    }
                } label: {
                    Text(exit.displayLabel)
                        .font(ClearskyFont.ui(14, weight: .medium))
                        .foregroundStyle(ClearskyColor.inkNavy)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: ClearskyMetric.minHitTarget)
                        .background(
                            RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                                .fill(ClearskyColor.surfaceSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                                .stroke(ClearskyColor.hairlineStrong, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A plain row for every promise that is not `.needsANewPlan` — "We made plans"
/// (`.planned`), "Waiting on them" (`.waitingOnThem`), Kept and Released.
private struct PromiseRow: View {
    let promise: Promise
    let isDirectlyCompletable: Bool
    let isWaitingOnThem: Bool
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: ClearskySpacing.m) {
            indicator

            VStack(alignment: .leading, spacing: 2) {
                Text(promise.personName)
                    .font(ClearskyFont.ui(14, weight: .medium))
                    .foregroundStyle(ClearskyColor.body)
                Text(promise.whatWasPromised)
                    .font(ClearskyFont.ui(12))
                    .foregroundStyle(ClearskyColor.muted)
                    .lineLimit(1)
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

    /// "Waiting on them cannot be completed using a checkbox/tap-to-complete
    /// interaction" (`CLAUDE_CODE_AUDIT.md` §"Promise ownership") — rendered here as
    /// the root `README.md`'s own wording puts it: "dashed circle, not tickable".
    /// Everything else that is directly completable (today, only `.planned`) gets a
    /// real tap target; everything else again (already-resolved Kept/Released) gets a
    /// plain, inert dot.
    @ViewBuilder
    private var indicator: some View {
        if isWaitingOnThem {
            Circle()
                .stroke(ClearskyColor.muted, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 20, height: 20)
        } else if isDirectlyCompletable {
            Button(action: onComplete) {
                Circle()
                    .stroke(ClearskyColor.hairlineStrong, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        } else {
            Circle()
                .fill(ClearskyColor.surfaceSecondary)
                .frame(width: 20, height: 20)
        }
    }
}

/// The "Give it a new time" sheet: a date picker for a promise's replacement due
/// date, presented per `PromiseNeedsANewPlanExit.giveItANewTime`'s doc comment. Saving
/// hands the picked date back to the caller, which is the only place that touches
/// `TriageStateMachine`/`PromiseStore` — this sheet is presentation only.
private struct GiveItANewTimeSheet: View {
    let promise: Promise
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newDueDate: Date

    init(promise: Promise, onSave: @escaping (Date) -> Void) {
        self.promise = promise
        self.onSave = onSave
        _newDueDate = State(initialValue: promise.dueDate)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ClearskySpacing.l) {
                Text("Give it a new time")
                    .font(ClearskyFont.display(22))
                    .foregroundStyle(ClearskyColor.inkNavy)
                    .displayHeadlineStyle()

                Text("\(promise.personName) \u{2014} \(promise.whatWasPromised)")
                    .font(ClearskyFont.editorial(15))
                    .foregroundStyle(ClearskyColor.body)
                    .fixedSize(horizontal: false, vertical: true)

                DatePicker(
                    "New due date",
                    selection: $newDueDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .tint(ClearskyColor.inkNavy)

                Spacer()

                Button {
                    onSave(newDueDate)
                    dismiss()
                } label: {
                    Text("Save new time")
                        .font(ClearskyFont.ui(16, weight: .semibold))
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
            .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ClearskyColor.secondaryInk)
                }
            }
        }
    }
}

// MARK: - Previews

/// Sample promises covering all four `PromiseOwnershipGroup` sections, including one
/// `.needsANewPlan` item, so the preview exercises every branch `row(for:)` can take.
/// Kept local to this file rather than added to `SampleData.swift`, which is out of
/// scope for this task.
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
        id: "preview-needs-a-new-plan",
        personName: "James Okafor",
        whatWasPromised: "Call about the lease renewal",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24),
        protectedTime: false,
        state: .needsANewPlan
    ),
    Promise(
        id: "preview-waiting-on-them",
        personName: "Priya Patel",
        whatWasPromised: "Confirm the venue for Saturday",
        dueDate: Date().addingTimeInterval(60 * 60 * 24 * 3),
        protectedTime: false,
        state: .waitingOnThem
    ),
    Promise(
        id: "preview-kept",
        personName: "Diego Ruiz",
        whatWasPromised: "Brought the hiking map",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 5),
        protectedTime: false,
        state: .kept
    ),
    Promise(
        id: "preview-released",
        personName: "Sam Rivera",
        whatWasPromised: "Old coffee catch-up, no longer happening",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 10),
        protectedTime: false,
        state: .released
    )
]

/// Builds a disposable, file-backed store pre-loaded with `previewPromises` — a real
/// temp file per preview run (same isolation pattern `PromiseStoreTests` uses) so
/// previews never read or pollute a real device's Documents directory.
@MainActor
private func makePreviewStore() -> PromiseStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("promises-view-preview-\(UUID().uuidString)")
        .appendingPathExtension("json")
    let store = PromiseStore(fileURL: url)
    for promise in previewPromises {
        store.add(promise)
    }
    return store
}

/// A no-op `CalendarHolding` for previews only — never grants access, so a preview
/// run never attempts a real EventKit call. Mirrors `RootView.swift`'s own
/// `PreviewCalendarService`; kept as a separate (file-scoped `private`) copy here
/// rather than shared, since neither file exposes its preview-only type to the other.
private struct PreviewCalendarService: CalendarHolding {
    func requestAccess() async throws -> Bool { false }
    func createHold(for block: ProtectedTimeBlock) async throws -> String { "preview-event" }
    func removeHold(eventIdentifier: String) async throws {}
}

#Preview("Promises") {
    PromisesView(store: makePreviewStore(), calendarService: PreviewCalendarService())
}
