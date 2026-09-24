/// One row of the canonical transition table: a starting state, the action that fires
/// it, the resulting state, and a note on what a real caller should record when it
/// applies that action. `requiredMetadata` is documentation only — this type does not
/// enforce that callers actually captured it.
public struct TriageTransitionRule: Equatable, Hashable, Sendable {
    public let from: Outcome
    public let action: TriageAction
    public let to: Outcome
    public let requiredMetadata: String

    public init(from: Outcome, action: TriageAction, to: Outcome, requiredMetadata: String) {
        self.from = from
        self.action = action
        self.to = to
        self.requiredMetadata = requiredMetadata
    }
}

/// Validates and applies transitions between `Outcome` states.
///
/// `table` is the single source of truth for which (state, action) pairs are legal. It
/// mirrors the canonical transition table in `CLAUDE_CODE_AUDIT.md`
/// §"Triage decision and state machine" row for row; a table row with multiple "from"
/// states there is expanded into one rule per source state here, so lookups stay a
/// simple, exhaustive scan and no (state, action) pair outside this list can ever
/// resolve to a next state.
public enum TriageStateMachine {

    /// The canonical, closed set of legal transitions. Any (from, action) pair not
    /// listed here is illegal: `canTransition` returns `nil` and `transition` throws.
    public static let table: [TriageTransitionRule] = [
        TriageTransitionRule(
            from: .needsAttention,
            action: .sendReply,
            to: .responded,
            requiredMetadata: "message/thread ID, sent timestamp"
        ),
        TriageTransitionRule(
            from: .needsAttention,
            action: .confirmPlan,
            to: .planned,
            requiredMetadata: "person, date/time, event/thread reference"
        ),
        TriageTransitionRule(
            from: .needsAttention,
            action: .chooseRevisitTime,
            to: .snoozed,
            requiredMetadata: "exact return timestamp"
        ),
        TriageTransitionRule(
            from: .needsAttention,
            action: .markAwaitingReply,
            to: .waitingOnThem,
            requiredMetadata: "awaited person, initial action/time"
        ),
        TriageTransitionRule(
            from: .responded,
            action: .markAwaitingReply,
            to: .waitingOnThem,
            requiredMetadata: "awaited person, initial action/time"
        ),
        TriageTransitionRule(
            from: .needsAttention,
            action: .letGo,
            to: .released,
            requiredMetadata: "reason optional, timestamp"
        ),
        TriageTransitionRule(
            from: .planned,
            action: .letGo,
            to: .released,
            requiredMetadata: "reason optional, timestamp"
        ),
        TriageTransitionRule(
            from: .needsANewPlan,
            action: .letGo,
            to: .released,
            requiredMetadata: "reason optional, timestamp"
        ),
        TriageTransitionRule(
            from: .planned,
            action: .completeCommitment,
            to: .kept,
            requiredMetadata: "completion timestamp, optional moment"
        ),
        TriageTransitionRule(
            from: .planned,
            action: .dateNoLongerWorks,
            to: .needsANewPlan,
            requiredMetadata: "prior date, reason optional"
        ),
        TriageTransitionRule(
            from: .snoozed,
            action: .returnDateArrives,
            to: .needsAttention,
            requiredMetadata: "return reason and current priority rationale"
        ),
        TriageTransitionRule(
            from: .needsANewPlan,
            action: .reschedulePlan,
            to: .planned,
            requiredMetadata: "prior date, prior person/thread, new date/time"
        )
    ]

    /// Returns the resulting `Outcome` if `action` is a legal transition from `state`,
    /// or `nil` if that (state, action) pair is not in the canonical table.
    public static func canTransition(from state: Outcome, via action: TriageAction) -> Outcome? {
        table.first { $0.from == state && $0.action == action }?.to
    }

    /// The rule matched for `state`/`action`, if any — carries `requiredMetadata` for
    /// callers that want to surface it.
    public static func rule(for state: Outcome, via action: TriageAction) -> TriageTransitionRule? {
        table.first { $0.from == state && $0.action == action }
    }

    public enum TransitionError: Error, Equatable, Sendable {
        case illegalTransition(from: Outcome, action: TriageAction)
    }

    /// Applies `action` to `state`, returning the resulting `Outcome`.
    /// Throws `TransitionError.illegalTransition` if the pair is not in the
    /// canonical table — it is impossible to reach any `Outcome` through an
    /// unlisted transition via this function.
    @discardableResult
    public static func transition(from state: Outcome, via action: TriageAction) throws -> Outcome {
        guard let next = canTransition(from: state, via: action) else {
            throw TransitionError.illegalTransition(from: state, action: action)
        }
        return next
    }
}
