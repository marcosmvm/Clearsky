import Foundation

/// The structured explanation behind a triage item's placement and recommended
/// action.
///
/// Mirrors the `TriageExplanation` sketch in `CLAUDE_CODE_AUDIT.md`
/// §"Why now and consequence". Storing structured signals and a next-review time as
/// data — rather than copy strings sprinkled through components — keeps the logic
/// testable, localizable and consistent across Today, Triage, Promises, Calendar,
/// notifications and recap surfaces.
public struct TriageExplanation: Equatable, Sendable {

    /// The real, named signals an item's `whyNow` explanation is built from.
    public enum Signal: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
        case innerCircle
        case directQuestion
        case promiseDue
        case waitingDuration
        case recentChange
        case snoozeReturn
    }

    /// The closed set of actions a triage card can recommend or offer as a quieter
    /// alternative. `recommendedAction` and `alternativeActions` are restricted to
    /// this type rather than a free-form string so an invalid action can never be
    /// stored or rendered.
    public enum RecommendedAction: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
        case respond
        case plan
        case snooze
        case wait
        case letGo
    }

    /// The human-readable reason this item surfaced now, e.g. "Inner circle · asked
    /// you a direct question · waiting 3 days".
    public var whyNow: String

    /// The real signals `whyNow` is built from.
    public var signals: [Signal]

    /// What happens if the user takes no action on this item.
    public var ifNoAction: String

    /// When this item should next be reviewed, if known — for example a snooze
    /// return time or a due promise date.
    public var nextReviewAt: Date?

    /// The one action selected from this item's own context.
    public var recommendedAction: RecommendedAction

    /// Quieter alternatives to the recommended action.
    public var alternativeActions: [RecommendedAction]

    public init(
        whyNow: String,
        signals: [Signal],
        ifNoAction: String,
        nextReviewAt: Date? = nil,
        recommendedAction: RecommendedAction,
        alternativeActions: [RecommendedAction] = []
    ) {
        self.whyNow = whyNow
        self.signals = signals
        self.ifNoAction = ifNoAction
        self.nextReviewAt = nextReviewAt
        self.recommendedAction = recommendedAction
        self.alternativeActions = alternativeActions
    }
}
