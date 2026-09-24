/// The eight named states a triage item can be in.
///
/// This vocabulary is canonical across the whole product: the data model, UI copy,
/// analytics events and notifications must all use these exact names — never a
/// synonym, and never the retired word for "Needs a new plan". See
/// `CLAUDE_CODE_AUDIT.md` §"Triage decision and state machine" for the source table
/// this type encodes.
public enum Outcome: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case needsAttention
    case responded
    case planned
    case snoozed
    case waitingOnThem
    case needsANewPlan
    case kept
    case released
}
