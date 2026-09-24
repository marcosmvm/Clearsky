import Foundation

/// A commitment: what was said, to whom, by when, and whether it holds a protected
/// calendar block.
///
/// `01 Product Scope.dc.html` §5 Object model defines the "Promise" entity as "what
/// was said, to whom, due date, source thread, protected-time flag, state (open,
/// kept, slipped, released)" — this type is that entity, expressed in code for the
/// first time in `ClearskyCore`. Everything up to now (`TriageStateMachine`,
/// `TriageAction`, `PromiseOwnership`) reasons about the eight-state `Outcome`
/// vocabulary in the abstract; `Promise` is the first concrete record that vocabulary
/// describes the state of.
///
/// There is no `Person` domain model yet, so — matching the app layer's existing
/// `TriageItem` pattern (`ios/ClearskyApp/ClearskyApp/SampleData.swift`) — `Promise`
/// identifies who it is for with a plain `personName` string rather than a typed
/// reference. `sourceThread` from the spec's field list is represented here as
/// `sourceText`, the original shared text a promise was captured from (see
/// `CapturedPromiseDraft`) — `nil` for a promise entered by hand rather than pulled
/// from a share.
///
/// Per `01 Product Scope.dc.html` §6 Screen inventory, "New promise": "What was said,
/// three time presets plus a picker, protect-the-time toggle" — a due date is always
/// supplied at creation, never optional or filled in later, so `dueDate` is a plain
/// `Date`, not `Date?`. A promise created this way always starts life scheduled, so
/// `state` starts at `.planned` — "a scheduled commitment the user owns keeping" per
/// `PromiseOwnership.swift` — never `.needsAttention` or any other `Outcome` case;
/// later triage/state-machine transitions are what move it elsewhere. `state` is
/// declared `var`, unlike every other field, because it is the one thing about a
/// promise that changes after creation.
public struct Promise: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: String
    public let personName: String
    public let whatWasPromised: String
    public let dueDate: Date
    /// The original shared text this promise was captured from, if any. `nil` for a
    /// promise entered by hand on the New promise screen.
    public let sourceText: String?
    /// The protect-the-time toggle from the New promise screen — whether this
    /// promise's due date should claim a protected calendar block (see
    /// `ProtectedTimeBlock`) rather than an ordinary one.
    public let protectedTime: Bool
    public var state: Outcome

    /// Creates a new promise. `state` defaults to `.planned` — a New promise always
    /// has a date at creation (per §6's "three time presets plus a picker"), so it is
    /// always scheduled, never left in an undecided state.
    public init(
        id: String,
        personName: String,
        whatWasPromised: String,
        dueDate: Date,
        sourceText: String? = nil,
        protectedTime: Bool,
        state: Outcome = .planned
    ) {
        self.id = id
        self.personName = personName
        self.whatWasPromised = whatWasPromised
        self.dueDate = dueDate
        self.sourceText = sourceText
        self.protectedTime = protectedTime
        self.state = state
    }
}
