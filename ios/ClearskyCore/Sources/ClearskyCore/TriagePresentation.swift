/// One action a triage card can offer — the recommended action or a quieter
/// alternative — resolved against the item's *current* `Outcome` into the exact
/// `TriageAction` a tap fires and the exact `Outcome` it lands on.
///
/// `TriageExplanation` only stores a `RecommendedAction` (a five-case UI vocabulary:
/// respond / plan / snooze / wait / let go). That vocabulary does not line up 1:1 with
/// `TriageAction` (the eight-case state-machine vocabulary `TriageStateMachine.table`
/// is keyed on) — see `TriagePresentation.triageAction(for:from:)` for the mapping and
/// its documented gaps. A `TriageResolvedAction` is the result of running that mapping
/// and then checking the outcome against `TriageStateMachine.canTransition`, so a card
/// can render "tap this → item becomes Responded" from data alone, never by importing
/// or re-deriving the transition table itself.
public struct TriageResolvedAction: Equatable, Hashable, Sendable {

    /// The `TriageExplanation.RecommendedAction` this was resolved from — either the
    /// item's `recommendedAction` or one entry of its `alternativeActions`.
    public let source: TriageExplanation.RecommendedAction

    /// The concrete state-machine action a tap on this button fires.
    public let triageAction: TriageAction

    /// The `Outcome` the item lands on after that action — read straight from
    /// `TriageStateMachine.table` via `canTransition`, never recomputed here.
    public let resultingState: Outcome

    public init(source: TriageExplanation.RecommendedAction, triageAction: TriageAction, resultingState: Outcome) {
        self.source = source
        self.triageAction = triageAction
        self.resultingState = resultingState
    }
}

/// Everything a Today/Triage card needs to render one item, with the transition table
/// already resolved — the missing connective piece the package README asks for:
/// "Prefer a single `deriveTriagePresentation()` that returns whyNow, ifNoAction,
/// recommendedAction, alternatives and nextReviewAt" (`ios/ClearskyCore/README.md`,
/// itself quoting the repository root `README.md` §"State management").
///
/// `TriageExplanation` already carries whyNow / signals / ifNoAction / nextReviewAt /
/// recommendedAction / alternativeActions as static data. What it cannot answer on its
/// own is "and if I tap that, what does this item become?" — that needs the item's
/// current `Outcome` plus `TriageStateMachine`. `TriagePresentation.build` does exactly
/// that lookup once, so the UI layer never has to import or reason about
/// `TriageStateMachine.table` itself; see `CLAUDE_CODE_AUDIT.md` §"Why now and
/// consequence", which asks every Today/Triage card to be able to show "the exact
/// resulting state for each action".
public struct TriagePresentation: Equatable, Sendable {

    /// The item's outcome *before* any action in this presentation is taken.
    public let state: Outcome

    /// The structured why-now/consequence explanation this presentation was built from.
    public let explanation: TriageExplanation

    /// `explanation.recommendedAction` resolved to a concrete action and resulting
    /// state, or `nil` if that recommendation has no legal transition from `state`.
    ///
    /// This should never be `nil` for well-formed data — whatever builds a
    /// `TriageExplanation` is expected to pick a `recommendedAction` that is legal for
    /// the item's own current state. `build(state:explanation:)` still resolves it
    /// defensively rather than force-unwrapping, for the same reason `alternatives`
    /// drops illegal entries instead of crashing: the UI must never be handed a button
    /// that would throw if tapped.
    public let recommended: TriageResolvedAction?

    /// `explanation.alternativeActions`, each resolved the same way as `recommended`,
    /// with any entry that has no legal transition from `state` silently dropped.
    ///
    /// This is a defensive guard, not an expected outcome: a well-behaved
    /// `TriageExplanation` should only ever list alternatives that are legal from the
    /// item's current state. Dropping instead of crashing means a stale or
    /// inconsistently-built explanation degrades to fewer buttons on the card rather
    /// than taking the app down.
    public let alternatives: [TriageResolvedAction]

    public init(
        state: Outcome,
        explanation: TriageExplanation,
        recommended: TriageResolvedAction?,
        alternatives: [TriageResolvedAction]
    ) {
        self.state = state
        self.explanation = explanation
        self.recommended = recommended
        self.alternatives = alternatives
    }

    // MARK: - RecommendedAction -> TriageAction mapping

    /// Maps a `TriageExplanation.RecommendedAction` to the `TriageAction` it fires,
    /// contingent on the item's current `state` — returning `nil` if that pairing is
    /// not a legal transition per `TriageStateMachine.table`.
    ///
    /// The two vocabularies do not line up 1:1:
    /// - `TriageAction` has eight cases keyed to specific `(from, to)` pairs in the
    ///   canonical table (`sendReply`, `confirmPlan`, `chooseRevisitTime`,
    ///   `markAwaitingReply`, `letGo`, `completeCommitment`, `dateNoLongerWorks`,
    ///   `returnDateArrives`).
    /// - `RecommendedAction` has five cases, one per triage-card button (`respond`,
    ///   `plan`, `snooze`, `wait`, `letGo`), written from the card's point of view
    ///   rather than the state machine's.
    ///
    /// Each `RecommendedAction` corresponds to exactly one candidate `TriageAction` —
    /// the vocabulary mapping itself does not branch on `state` — but *legality* does
    /// depend on `state`, because several `TriageAction`s are only legal from certain
    /// source states (`markAwaitingReply` is legal from both `.needsAttention` and
    /// `.responded`; `letGo` is legal from `.needsAttention`, `.planned` and
    /// `.needsANewPlan`). That is why this function takes `state` and consults
    /// `TriageStateMachine.canTransition` rather than returning a bare `TriageAction`:
    /// callers get `nil` for free whenever the pairing would be illegal, instead of
    /// having to re-check the table themselves.
    ///
    /// | RecommendedAction | candidate TriageAction | legal from |
    /// |---|---|---|
    /// | `.respond` | `.sendReply` | `.needsAttention` |
    /// | `.plan` | `.confirmPlan` | `.needsAttention` |
    /// | `.snooze` | `.chooseRevisitTime` | `.needsAttention` |
    /// | `.wait` | `.markAwaitingReply` | `.needsAttention`, `.responded` |
    /// | `.letGo` | `.letGo` | `.needsAttention`, `.planned`, `.needsANewPlan` |
    ///
    /// **Known open seam, not fixed here.** `CLAUDE_CODE_AUDIT.md` §"Promise ownership"
    /// expects "Needs a new plan" to offer "give it a new time" as a recovery action,
    /// which reads as the `.plan` recommendation. But `TriageStateMachine.table` has no
    /// `(from: .needsANewPlan, action: .confirmPlan)` row — the only legal action from
    /// `.needsANewPlan` is `.letGo` — so `triageAction(for: .plan, from: .needsANewPlan)`
    /// correctly returns `nil` per the table as it stands today, and that leaves "give
    /// it a new time" with no `RecommendedAction` this function can resolve. Closing
    /// that gap needs either a new table row (some "replan" `TriageAction` from
    /// `.needsANewPlan` to `.planned`) or a product decision that "give it a new time"
    /// lives outside the Today/Triage card's `RecommendedAction` model entirely (e.g.
    /// Promise Detail only) — both are changes to `TriageStateMachine.swift` /
    /// `TriageAction.swift`, which this task must not edit. Flagged here and in the PR
    /// description instead of forced through.
    ///
    /// Separately, three `TriageAction` cases have no `RecommendedAction` counterpart
    /// at all — `.completeCommitment`, `.dateNoLongerWorks`, `.returnDateArrives` — so
    /// this function can never produce them. That reads as intentional rather than a
    /// gap: those three behave like Promise Detail actions or a snooze timer firing
    /// ("keep it", "give it a new time" on the promise itself, the return-date arriving
    /// on its own), not Today/Triage card recommendations, so they sit outside
    /// `TriageExplanation`'s five-case vocabulary by design.
    public static func triageAction(
        for recommended: TriageExplanation.RecommendedAction,
        from state: Outcome
    ) -> TriageAction? {
        resolvedLegalAction(for: recommended, from: state)?.action
    }

    // MARK: - Builder

    /// Resolves `explanation.recommendedAction` and every entry of
    /// `explanation.alternativeActions` against `state` via `TriageStateMachine`, and
    /// bundles the result with `state` and `explanation` into one `TriagePresentation`
    /// a UI layer can render without ever consulting the transition table itself.
    ///
    /// Any alternative action with no legal transition from `state` is silently
    /// dropped — see `alternatives` above for why that is a deliberate defensive guard
    /// rather than a bug to be surfaced louder. `recommended` is resolved the same
    /// defensive way and may also come back `nil`.
    public static func build(state: Outcome, explanation: TriageExplanation) -> TriagePresentation {
        let recommended = resolvedLegalAction(for: explanation.recommendedAction, from: state).map {
            TriageResolvedAction(
                source: explanation.recommendedAction,
                triageAction: $0.action,
                resultingState: $0.resultingState
            )
        }

        let alternatives = explanation.alternativeActions.compactMap { alternative in
            resolvedLegalAction(for: alternative, from: state).map {
                TriageResolvedAction(
                    source: alternative,
                    triageAction: $0.action,
                    resultingState: $0.resultingState
                )
            }
        }

        return TriagePresentation(state: state, explanation: explanation, recommended: recommended, alternatives: alternatives)
    }

    // MARK: - Private

    /// The fixed `RecommendedAction` -> `TriageAction` vocabulary mapping (see the
    /// table in `triageAction(for:from:)`'s doc comment). This mapping alone does not
    /// decide legality — it only names the candidate action to check.
    private static func candidateTriageAction(for recommended: TriageExplanation.RecommendedAction) -> TriageAction {
        switch recommended {
        case .respond: return .sendReply
        case .plan: return .confirmPlan
        case .snooze: return .chooseRevisitTime
        case .wait: return .markAwaitingReply
        case .letGo: return .letGo
        }
    }

    /// Looks up the candidate `TriageAction` for `recommended`, then confirms it
    /// against `TriageStateMachine.canTransition` — the single place this file
    /// consults the state machine, rather than re-implementing its legality rules.
    private static func resolvedLegalAction(
        for recommended: TriageExplanation.RecommendedAction,
        from state: Outcome
    ) -> (action: TriageAction, resultingState: Outcome)? {
        let candidate = candidateTriageAction(for: recommended)
        guard let resultingState = TriageStateMachine.canTransition(from: state, via: candidate) else {
            return nil
        }
        return (candidate, resultingState)
    }
}
