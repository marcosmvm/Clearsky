/// The Promises list groups promises by who owns the next move, not by raw status.
///
/// Mirrors `CLAUDE_CODE_AUDIT.md` §"Promise ownership", which requires: "Promises are
/// grouped by ownership/kind rather than only by status", that "'I'll reach out' and
/// 'We made plans' appear under Yours to keep", that "'Waiting on them' appears under
/// Not your move", and that "Waiting on them cannot be completed using a
/// checkbox/tap-to-complete interaction". The root `README.md` "Interactions and
/// behaviour" section confirms the same four-group shape: "*Yours to keep* (I'll reach
/// out / We made plans), *Not your move* (Waiting on them — dashed circle, not
/// tickable), then Kept and Released."
///
/// Case names double as the UI section headers, spelled exactly as the audit doc and
/// README give them, so a view can render `group.displayTitle` directly instead of
/// re-deriving copy from the `Outcome` in the section body.
public enum PromiseOwnershipGroup: String, CaseIterable, Equatable, Hashable, Sendable, Codable {

    /// "I'll reach out" and "We made plans" — the user still owes the next move.
    /// Also where `.needsANewPlan` lives; see `PromiseOwnership.group(for:)`.
    case yoursToKeep

    /// "Waiting on them" — the other person owes the next move. Never render a
    /// checkbox or tap-to-complete affordance for a promise in this group; see
    /// `PromiseOwnership.isDirectlyCompletable(_:)`.
    case notYourMove

    /// The promise was completed.
    case kept

    /// The promise was let go, with or without a replacement plan.
    case released

    /// The exact section heading the audit doc and README use for this group.
    public var displayTitle: String {
        switch self {
        case .yoursToKeep: return "Yours to keep"
        case .notYourMove: return "Not your move"
        case .kept: return "Kept"
        case .released: return "Released"
        }
    }
}

/// Promise-list presentation rules derived from `Outcome`.
///
/// Kept separate from `TriageStateMachine` on purpose: grouping and completability are
/// presentation-layer decisions about *how a state is shown on the Promises list*, not
/// transitions between states. Centralising them here — instead of in a view — means a
/// screen can never independently re-derive (and mis-derive) which group a promise
/// belongs in or whether it may be tap-completed.
public enum PromiseOwnership {

    /// Maps an `Outcome` to the `PromiseOwnershipGroup` it displays under on the
    /// Promises list, or `nil` if that `Outcome` should never appear there at all.
    ///
    /// - `.planned` → `.yoursToKeep` ("We made plans" — a scheduled commitment the
    ///   user owns keeping).
    /// - `.needsANewPlan` → `.yoursToKeep`. The audit doc names exactly four groups
    ///   (Yours to keep / Not your move / Kept / Released) and does not define a fifth
    ///   for this state — and it must not: `.needsANewPlan` is still owned by the
    ///   user (the original date stopped working, but nobody released the promise),
    ///   it is still actionable (the audit doc requires "clear, non-shaming recovery
    ///   actions" and three named exits — see `PromiseNeedsANewPlanExit`), and per the
    ///   task brief it must never disappear from the list. Grouping it under
    ///   "Yours to keep" keeps that ownership honest without inventing UI the source
    ///   docs never asked for; the recovery framing (never the retired word this
    ///   product no longer uses for a missed date, never red/error treatment) is a
    ///   presentation detail for the view layer, not a different group.
    /// - `.waitingOnThem` → `.notYourMove` ("Waiting on them" per the audit doc,
    ///   verbatim).
    /// - `.kept` → `.kept`, `.released` → `.released`.
    /// - `.needsAttention`, `.responded`, `.snoozed` → `nil`. These three are
    ///   triage-only states: they describe an inbound item still being worked through
    ///   Triage (needs a reply, was replied to, or was snoozed for later triage), not
    ///   a promise the user has made or is owed. A screen with a triage item cannot
    ///   yet be a "promise" in the ownership sense the audit doc groups, so it is
    ///   intentionally excluded here rather than silently defaulting into a group.
    public static func group(for outcome: Outcome) -> PromiseOwnershipGroup? {
        switch outcome {
        case .planned, .needsANewPlan:
            return .yoursToKeep
        case .waitingOnThem:
            return .notYourMove
        case .kept:
            return .kept
        case .released:
            return .released
        case .needsAttention, .responded, .snoozed:
            return nil
        }
    }

    /// Whether a promise in this `Outcome` may be completed with a direct
    /// tap/checkbox interaction on the Promises list.
    ///
    /// This is the core invariant from the audit doc: "Waiting on them cannot be
    /// completed using a checkbox/tap-to-complete interaction" — because the next
    /// move belongs to the other person, not the user. Rather than re-deriving that
    /// rule ad hoc in a view (and risking it drifting from the canonical rules), this
    /// asks `TriageStateMachine` directly whether `.completeCommitment` is a legal
    /// transition out of `outcome`: the table in `TriageStateMachine.swift` lists
    /// exactly one such row (`.planned` → `.kept`), so this function and the state
    /// machine can never disagree.
    ///
    /// Concretely: `true` only for `.planned` (the one state with a legal
    /// `.completeCommitment` transition). `false` for every other state, including
    /// `.waitingOnThem` (no completion path at all — see
    /// `TriageStateMachineTests.testWaitingOnThemCannotBeCompletedDirectlyToKept`),
    /// `.needsANewPlan` (neither of its legal transitions, `.letGo` nor
    /// `.reschedulePlan`, is `.completeCommitment`; recovering it needs one of the
    /// three named exits below, not a bare tap), and `.kept`/`.released` (already
    /// resolved — there is nothing left to complete).
    public static func isDirectlyCompletable(_ outcome: Outcome) -> Bool {
        TriageStateMachine.canTransition(from: outcome, via: .completeCommitment) != nil
    }
}

/// The three named exits offered on the Promise detail screen for a promise in
/// `.needsANewPlan`.
///
/// Matches `CLAUDE_CODE_AUDIT.md` §"Promise ownership" verbatim: "Promise detail
/// offers keep it, give it a new time, and let it go." The root `README.md` repeats
/// the same three: "it offers three honest exits: keep it, give it a new time, let it
/// go." A closed enum — rather than a free-form string — means the detail screen can
/// never offer a fourth, differently worded, or shaming exit by accident.
///
/// This type is UI-facing vocabulary only. It intentionally does not wire into
/// `TriageStateMachine.TriageAction`/`table` directly — that transition table is out
/// of scope for this file (see `ios/ClearskyCore/README.md` and the task that added
/// this file). The table now has two outgoing rules for `.needsANewPlan`: `.letGo` →
/// `.released` and `.reschedulePlan` → `.planned`, the latter added so
/// `.giveItANewTime` has a legal transition to resolve through. Wiring each of the
/// three UI exits to its transition (`.keepIt` reaffirms the existing plan and has no
/// table row by design; `.giveItANewTime` resolves via
/// `TriageStateMachine.transition(from: .needsANewPlan, via: .reschedulePlan)`;
/// `.letItGo` via `.letGo`) is done by whoever wires up the Promise detail screen, not
/// by this pure domain type.
public enum PromiseNeedsANewPlanExit: String, CaseIterable, Equatable, Hashable, Sendable, Codable {

    /// "Keep it" — the plan still stands as-is; the user reaffirms the commitment.
    case keepIt

    /// "Give it a new time" — the commitment holds, but the date/time is replaced.
    /// Per the audit doc's remediation note, doing this should preserve the source
    /// thread, original wording, person and prior date — a UI/data concern for
    /// whichever layer implements this exit, not modeled by this enum case itself.
    /// Corresponds to the `TriageStateMachine.table` row `(from: .needsANewPlan,
    /// action: .reschedulePlan, to: .planned)`; resolving this exit calls
    /// `TriageStateMachine.transition(from: .needsANewPlan, via: .reschedulePlan)`.
    case giveItANewTime

    /// "Let it go" — the user releases the promise. Corresponds to the
    /// state-machine transition out of `.needsANewPlan`: `.letGo` → `.released`.
    case letItGo

    /// The exact phrase the audit doc and README use for this exit.
    public var displayLabel: String {
        switch self {
        case .keepIt: return "Keep it"
        case .giveItANewTime: return "Give it a new time"
        case .letItGo: return "Let it go"
        }
    }
}
