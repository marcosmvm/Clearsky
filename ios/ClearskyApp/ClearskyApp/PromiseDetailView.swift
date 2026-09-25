import SwiftUI
import ClearskyCore

/// The "Promise detail" screen: the full record of one commitment.
///
/// Per `01 Product Scope.dc.html` §6 Screen inventory, "Promise detail" — Purpose: "The
/// full record of one commitment". Key states/actions: "A status chip in the item's own
/// vocabulary (Needs a new plan · Upcoming · Waiting on them · Kept · Released), one
/// line naming what kind of commitment it is, the exact words it came from, a link back
/// to the thread, the protected-time toggle, and three exits: keep it, give it a new
/// time, or let it go." This view renders exactly that list, in that order, for a single
/// `Promise` — see the section-by-section breakdown below for where each element lives
/// and, for the two elements this codebase cannot yet fully honor, why.
///
/// Status chip: `Outcome.displayName`/`.statusColor` (`DomainDisplay.swift`) only —
/// never a hand-typed label, so this can never drift from, or accidentally invent a
/// synonym for, the one canonical vocabulary the rest of the product already uses
/// (`PromisesView.NeedsANewPlanCard` reads the same two properties the same way).
///
/// Link back to the thread: there is no Thread screen or domain model anywhere in this
/// codebase yet (`git grep -i thread` under `ios/` turns up nothing) — threads are out
/// of scope, deferred alongside the rest of Triage's message-thread work per
/// `PromiseOwnership.swift`'s own doc comment on `PromiseNeedsANewPlanExit`. `threadRow`
/// below renders a disabled, inert row so the layout still visually accounts for every
/// element the spec names, rather than either silently dropping it or building a fake
/// `NavigationLink` to a screen that does not exist.
///
/// Protected-time toggle: read-only here — it reflects `promise.protectedTime` but does
/// not let the user flip it from this screen. Making it interactively re-toggleable
/// means re-wiring the real EventKit calendar hold (`CalendarHolding.swift`,
/// `EventKitCalendarService.swift`), which is already in flight this shift as its own
/// piece of work; touching that wiring here would collide with it. See `protectedTimeRow`.
///
/// Three exits: rendered only when `promise.state == .needsANewPlan`, per
/// `PromisesView.row(for:)`'s existing rule that the exits are a `.needsANewPlan`-only
/// affordance — every other state (`.planned`, `.waitingOnThem`, `.kept`, `.released`,
/// etc.) shows the rest of the detail record with no exits at all. Uses
/// `PromiseNeedsANewPlanExit.allCases`/`.displayLabel` verbatim, the same enum
/// `PromisesView.NeedsANewPlanCard` renders, and resolves "give it a new time"/"let it
/// go" through the same two `TriageStateMachine.transition` calls
/// `PromisesView.giveItANewTime`/`letItGo` use — reimplemented directly in this file
/// (see `giveItANewTime(newDueDate:)`/`letItGo()` below) since those methods are private
/// to `PromisesView.swift`, which this task must not edit.
///
/// This view never talks to `PromiseStore` except through the injected instance, same
/// "no hidden state" pattern `PromisesView`/`NewPromiseView` already use — it takes
/// `store: PromiseStore` exactly as `PromisesView` does, rather than a bespoke save
/// closure, per the task note asking the three exits to persist through
/// `store.update(_:)` the same way. Wiring this screen into real navigation (a tap on a
/// `PromisesView` row pushing here) is a later, separate task — this file only needs to
/// compile and be previewable/testable standalone, and it adds no call site into
/// `PromisesView.swift`/`RootView.swift`.
struct PromiseDetailView: View {
    @ObservedObject var store: PromiseStore

    /// A local, mutable copy of the promise being shown. Seeded from the `promise`
    /// passed at `init`; each exit updates this alongside `store.update(_:)` so the
    /// screen reflects the new state/date immediately, the same instant the store
    /// persists it — mirrors `NewPromiseView`'s `@State` field pattern rather than
    /// re-reading `store.promises` by id, since this screen must render correctly even
    /// when previewed with a promise the store does not (yet) contain.
    @State private var promise: Promise

    /// Drives the "Give it a new time" sheet — `nil` when it is not showing. A plain
    /// `Bool` rather than `PromisesView`'s `Promise?` pattern since this screen only
    /// ever reschedules its own single `promise`.
    @State private var isShowingGiveItANewTimeSheet = false

    init(promise: Promise, store: PromiseStore) {
        _promise = State(initialValue: promise)
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClearskySpacing.xl) {
                header

                fieldSection(label: "THE EXACT WORDS") {
                    sourceTextContent
                }

                threadRow

                protectedTimeRow

                exitsSection
            }
            .padding(.horizontal, ClearskySpacing.l)
            .padding(.top, ClearskySpacing.m)
            .padding(.bottom, ClearskySpacing.xl)
        }
        .background(ClearskyColor.surfaceTertiary.ignoresSafeArea())
        .sheet(isPresented: $isShowingGiveItANewTimeSheet) {
            PromiseDetailGiveItANewTimeSheet(promise: promise) { newDueDate in
                giveItANewTime(newDueDate: newDueDate)
            }
        }
    }

    // MARK: - Header: status chip + the one-line summary

    private var header: some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
            statusChip

            Text(promise.personName)
                .font(ClearskyFont.display(24))
                .foregroundStyle(ClearskyColor.inkNavy)
                .displayHeadlineStyle()

            // "One line naming what kind of commitment it is": the same
            // `whatWasPromised` field every other screen (`PromisesView.PromiseRow`,
            // `PromisesView.NeedsANewPlanCard`, `NewPromiseView`) already treats as
            // that one line — never a second, separately hand-typed summary.
            Text(promise.whatWasPromised)
                .font(ClearskyFont.editorial(17))
                .foregroundStyle(ClearskyColor.body)
                .fixedSize(horizontal: false, vertical: true)

            Text(promise.dueDate.formatted(date: .abbreviated, time: .shortened))
                .font(ClearskyFont.ui(13))
                .foregroundStyle(ClearskyColor.muted)
        }
    }

    /// "A status chip in the item's own vocabulary" — `Outcome.displayName`/
    /// `.statusColor` only, exactly as `PromisesView.NeedsANewPlanCard.header` reads
    /// them for the one state it shows. This chip reads whichever `Outcome` `promise`
    /// is actually in, so it is correct for all five named states (Needs a new plan ·
    /// Upcoming · Waiting on them · Kept · Released) and the three internal-only
    /// `Outcome` cases (`needsAttention`/`responded`/`snoozed`) a promise never actually
    /// holds in practice.
    private var statusChip: some View {
        Text(promise.state.displayName)
            .font(ClearskyFont.ui(12, weight: .semibold))
            .foregroundStyle(promise.state.statusColor)
            .padding(.horizontal, ClearskySpacing.s)
            .padding(.vertical, ClearskySpacing.xxs)
            .background(
                Capsule().fill(promise.state.statusColor.opacity(0.12))
            )
    }

    // MARK: - The exact words it came from

    /// `sourceText` if this promise was captured from a share ("the exact words it came
    /// from," quoted verbatim, never paraphrased) — otherwise an honest statement that
    /// there is none, since a hand-entered promise (`NewPromiseView` opened with
    /// `draft: nil`) has no original wording to show. Never invents placeholder copy
    /// for the `nil` case.
    @ViewBuilder
    private var sourceTextContent: some View {
        if let sourceText = promise.sourceText, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("\u{201C}\(sourceText)\u{201D}")
                .font(ClearskyFont.editorial(15))
                .foregroundStyle(ClearskyColor.body)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Entered by hand — no source text")
                .font(ClearskyFont.ui(13))
                .foregroundStyle(ClearskyColor.muted)
        }
    }

    // MARK: - Link back to the thread (deferred — see the type doc comment above)

    private var threadRow: some View {
        HStack(spacing: ClearskySpacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(ClearskyColor.muted)
            Text("Linked thread")
                .font(ClearskyFont.ui(14, weight: .medium))
                .foregroundStyle(ClearskyColor.muted)
            Spacer()
            Text("Not available yet")
                .font(ClearskyFont.ui(12))
                .foregroundStyle(ClearskyColor.muted)
        }
        .padding(.horizontal, ClearskySpacing.m)
        .frame(minHeight: ClearskyMetric.minHitTarget)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.sm, style: .continuous)
                .fill(ClearskyColor.surfaceSecondary)
        )
        .opacity(0.6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Linked thread, not available yet")
    }

    // MARK: - Protected-time toggle (read-only — see the type doc comment above)

    private var protectedTimeRow: some View {
        Toggle(isOn: .constant(promise.protectedTime)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Protected time")
                    .font(ClearskyFont.ui(15, weight: .semibold))
                    .foregroundStyle(ClearskyColor.inkNavy)
                Text("Nothing else can be booked over it")
                    .font(ClearskyFont.ui(12))
                    .foregroundStyle(ClearskyColor.muted)
            }
        }
        .tint(ClearskyColor.inkNavy)
        .disabled(true)
        .padding(ClearskySpacing.m)
        .background(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .fill(ClearskyColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ClearskyRadius.md, style: .continuous)
                .stroke(ClearskyColor.hairline, lineWidth: 1)
        )
    }

    // MARK: - Three exits (needsANewPlan only)

    @ViewBuilder
    private var exitsSection: some View {
        if promise.state == .needsANewPlan {
            VStack(alignment: .leading, spacing: ClearskySpacing.sm) {
                Text("EXITS")
                    .font(ClearskyFont.ui(12, weight: .semibold))
                    .tracking(0.08 * 12)
                    .foregroundStyle(ClearskyColor.muted)

                VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
                    ForEach(PromiseNeedsANewPlanExit.allCases, id: \.self) { exit in
                        Button {
                            switch exit {
                            case .keepIt:
                                // "Keep it": no state change — the plan still stands as-
                                // is. Same no-op semantics as
                                // `PromisesView.NeedsANewPlanCard.onKeepIt`, and per
                                // `PromiseNeedsANewPlanExit.keepIt`'s own doc comment
                                // ("reaffirms the existing plan and has no table row by
                                // design").
                                break
                            case .giveItANewTime:
                                isShowingGiveItANewTimeSheet = true
                            case .letItGo:
                                letItGo()
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
    }

    // MARK: - Actions

    /// "Give it a new time": same resolution `PromisesView.giveItANewTime` uses —
    /// `TriageStateMachine.transition(from: .needsANewPlan, via: .reschedulePlan)` —
    /// reimplemented here rather than called into that file's private method, which
    /// this task must not edit. Replaces `dueDate` with the picked value and `state`
    /// with the returned `.planned`, then saves through the store, exactly matching
    /// `PromisesView.giveItANewTime`'s own field-by-field rebuild (including that it
    /// does not carry `calendarEventIdentifier` forward — same as that method).
    private func giveItANewTime(newDueDate: Date) {
        guard let next = try? TriageStateMachine.transition(from: .needsANewPlan, via: .reschedulePlan) else { return }
        let updated = Promise(
            id: promise.id,
            personName: promise.personName,
            whatWasPromised: promise.whatWasPromised,
            dueDate: newDueDate,
            sourceText: promise.sourceText,
            protectedTime: promise.protectedTime,
            state: next
        )
        promise = updated
        store.update(updated)
    }

    /// "Let it go": same resolution `PromisesView.letItGo` uses —
    /// `TriageStateMachine.transition(from: .needsANewPlan, via: .letGo)`.
    private func letItGo() {
        guard let next = try? TriageStateMachine.transition(from: .needsANewPlan, via: .letGo) else { return }
        var updated = promise
        updated.state = next
        promise = updated
        store.update(updated)
    }

    // MARK: - Layout helper

    @ViewBuilder
    private func fieldSection<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ClearskySpacing.xs) {
            Text(label)
                .font(ClearskyFont.ui(11, weight: .semibold))
                .tracking(0.08 * 11)
                .foregroundStyle(ClearskyColor.muted)
            content()
        }
    }
}

/// The "Give it a new time" sheet for `PromiseDetailView` — a standalone copy of
/// `PromisesView.GiveItANewTimeSheet`'s date-picker pattern (same visual language: same
/// tokens, same layout, same copy) since that type is private to `PromisesView.swift`,
/// which this task must not edit or import from.
private struct PromiseDetailGiveItANewTimeSheet: View {
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

/// Builds a disposable, file-backed store pre-loaded with `promise` — a real temp file
/// per preview run (same isolation pattern `PromisesView.swift`'s `makePreviewStore()`
/// and `PromiseStoreTests` use) so previews never read or pollute a real device's
/// Documents directory.
@MainActor
private func makePreviewStore(with promise: Promise) -> PromiseStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("promise-detail-preview-\(UUID().uuidString)")
        .appendingPathExtension("json")
    let store = PromiseStore(fileURL: url)
    store.add(promise)
    return store
}

#Preview("Planned, hand-entered") {
    let promise = Promise(
        id: "preview-planned",
        personName: "Maya Chen",
        whatWasPromised: "Send the invoice by Friday",
        dueDate: Date().addingTimeInterval(60 * 60 * 24 * 2),
        protectedTime: true,
        state: .planned
    )
    PromiseDetailView(promise: promise, store: makePreviewStore(with: promise))
}

#Preview("Needs a new plan, from a share") {
    let promise = Promise(
        id: "preview-needs-a-new-plan",
        personName: "James Okafor",
        whatWasPromised: "Call about the lease renewal",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24),
        sourceText: "Hey, can you call the landlord about renewing before the 1st? I keep forgetting.",
        protectedTime: false,
        state: .needsANewPlan
    )
    PromiseDetailView(promise: promise, store: makePreviewStore(with: promise))
}

#Preview("Kept") {
    let promise = Promise(
        id: "preview-kept",
        personName: "Diego Ruiz",
        whatWasPromised: "Brought the hiking map",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 5),
        protectedTime: false,
        state: .kept
    )
    PromiseDetailView(promise: promise, store: makePreviewStore(with: promise))
}

#Preview("Released") {
    let promise = Promise(
        id: "preview-released",
        personName: "Sam Rivera",
        whatWasPromised: "Old coffee catch-up, no longer happening",
        dueDate: Date().addingTimeInterval(-60 * 60 * 24 * 10),
        protectedTime: false,
        state: .released
    )
    PromiseDetailView(promise: promise, store: makePreviewStore(with: promise))
}
