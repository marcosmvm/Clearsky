/// The user actions that can move a triage item from one `Outcome` to another.
///
/// Each case corresponds to one action column in the canonical transition table in
/// `CLAUDE_CODE_AUDIT.md` §"Triage decision and state machine". A row in that table
/// with multiple "from" states (for example "Needs attention or Responded") shares a
/// single action case here; it is expanded into one `TriageTransitionRule` per source
/// state in `TriageStateMachine.table`.
public enum TriageAction: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    /// Needs attention → Responded.
    case sendReply
    /// Needs attention → Planned.
    case confirmPlan
    /// Needs attention → Snoozed.
    case chooseRevisitTime
    /// Needs attention or Responded → Waiting on them.
    case markAwaitingReply
    /// Needs attention / Planned / Needs a new plan → Released.
    case letGo
    /// Planned → Kept.
    case completeCommitment
    /// Planned → Needs a new plan.
    case dateNoLongerWorks
    /// Snoozed → Needs attention.
    case returnDateArrives
}
